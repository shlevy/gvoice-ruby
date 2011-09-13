# -*- encoding: utf-8 -*-
$:.unshift(File.dirname(__FILE__))
%w[curb nokogiri json sms voicemail call user logger compatibility inbox_parser open-uri errors].each { |lib| require lib }

module GvoiceRuby
  class Client
    include Curl
    
    attr_accessor :unread_counts, :smss, :voicemails, :user, :all_messages, :calls
    attr_reader :logger
    
    def initialize(config = GvoiceRuby::Configurator.load_config)
      if config[:google_account_email].nil? || config[:google_account_password].nil?
        raise ArgumentError, "Invalid Google Account username or password provided."
      else          
        @logger        = Logger.new(config.has_key?(:logfile) ? config[:logfile] :
                                      File.join(File.dirname(__FILE__), '..', '..', 'log', 'gvoice-ruby.log'))
        @user          = User.new(config[:google_account_email], config[:google_account_password])
        @any_unread    = []
        @unread_counts = {}
        @all_messages  = []
        initialize_curb
      end
      
      login(config)
      set_rnr_se_token
      # in case _rnr_se scraping fails due to google changing its page content
      @_rnr_se ||= config[:rnr_se]
    end
    
    def any_unread?
      @any_unread
    end
    
    def logged_in?
      !@curb_instance.nil?
    end
    
    def check(parser = GvoiceRuby::InboxParser.new)
      inbox = parser.parse_page(fetch_page)
      
      get_unread_counts(inbox)
      @smss = parser.parse_sms_messages(inbox['messages'])
      @voicemails = parser.parse_voicemail_messages(inbox['messages'])
      @all_messages = smss | voicemails
      @all_messages.sort_by!(&:start_time)
    end
    
    def missed(parser = GvoiceRuby::InboxParser.new)
      inbox = parser.parse_page(fetch_page('https://www.google.com/voice/inbox/recent/missed/'))
      parser.parse_calls(inbox['messages'])
    end
    
    def received(parser = GvoiceRuby::InboxParser.new)
      inbox = parser.parse_page(fetch_page('https://www.google.com/voice/inbox/recent/received/'))
      parser.parse_calls(inbox['messages'])
    end
    
    def placed(parser = GvoiceRuby::InboxParser.new)
      inbox = parser.parse_page(fetch_page('https://www.google.com/voice/inbox/recent/placed/'))
      parser.parse_calls(inbox['messages'])
    end
    
    def send_sms(options, show_details = true)
      fields = [ PostField.content('phoneNumber', options[:phone_number]),
                 PostField.content('text', options[:text]),
                 PostField.content('_rnr_se', @_rnr_se) ]

      options.merge!({ :post_url => "https://www.google.com/voice/sms/send" })

      if show_details
        logger.info "Sending sms..."
        logger.info "  To: #{options[:phone_number]}"
        logger.info "  Body: #{options[:text]}"
        logger.info "  At: #{Time.now}"
      end

      post(options, fields)
    end
    
    def call(options)
      fields = [ PostField.content('outgoingNumber', options[:outgoing_number]),
                 PostField.content('forwardingNumber', options[:forwarding_number]),
                 PostField.content('phoneType', options[:phone_type] || 2),
                 PostField.content('subscriberNumber', 'undefined'),
                 PostField.content('remember', 0),
                 PostField.content('_rnr_se', @_rnr_se) ]
      
      options.merge!({ :post_url => "https://www.google.com/voice/call/connect" })
                 
      post(options, fields)
    end
    
    def cancel_call(options = {})
      fields = [ PostField.content('outgoingNumber', options[:outgoing_number] || 'undefined'),
                 PostField.content('forwardingNumber', options[:forwarding_number] || 'undefined'),
                 PostField.content('cancelType', 'C2C'),
                 PostField.content('_rnr_se', @_rnr_se) ]
                 
      options.merge!({ :post_url => "https://www.google.com/voice/call/cancel" })
      
      post(options, fields)
    end
    
    def archive(options)
      fields = [ PostField.content('messages', options[:id]),
                 PostField.content('archive', 1),
                 PostField.content('_rnr_se', @_rnr_se) ]
                 
      options.merge!({ :post_url => 'https://www.google.com/voice/inbox/mark'})
                 
      post(options, fields)
    end
    
    def mark_as_read(options)
      fields = [ PostField.content('messages', options[:id]),
                 PostField.content('read', 1),
                 PostField.content('_rnr_se', @_rnr_se) ]
                 
      options.merge!({ :post_url => 'https://www.google.com/voice/inbox/mark'})
                 
      post(options, fields)
    end
    
    def mark_as_unread(options)
      fields = [ PostField.content('messages', options[:id]),
                 PostField.content('read', 0),
                 PostField.content('_rnr_se', @_rnr_se) ]
                 
      options.merge!({ :post_url => 'https://www.google.com/voice/inbox/mark'})
                 
      post(options, fields)
    end
    
    def star(options)
      fields = [ PostField.content('messages', options[:id]),
                 PostField.content('star', 1),
                 PostField.content('_rnr_se', @_rnr_se) ]
                 
      options.merge!({ :post_url => 'https://www.google.com/voice/inbox/star'})
                 
      post(options, fields)
    end
    
    def unstar(options)
      fields = [ PostField.content('messages', options[:id]),
                 PostField.content('star', 0),
                 PostField.content('_rnr_se', @_rnr_se) ]
                 
      options.merge!({ :post_url => 'https://www.google.com/voice/inbox/star'})
                 
      post(options, fields)
    end
    
    def add_note(options)
      fields = [ PostField.content('id', options[:id]),
                 PostField.content('note', options[:note]),
                 PostField.content('_rnr_se', @_rnr_se) ]
                 
      options.merge!({ :post_url => 'https://www.google.com/voice/inbox/savenote'})
      
      post(options, fields)
    end
    
    def delete_note(options)
      fields = [ PostField.content('id', options[:id]),
                 PostField.content('_rnr_se', @_rnr_se) ]
                 
      options.merge!({ :post_url => 'https://www.google.com/voice/inbox/deletenote'})
      
      post(options, fields)
    end
    
    def logout
      if logged_in?
        @curb_instance.url = "https://www.google.com/voice/account/signout"
        @curb_instance.perform
        logger.info "FINISHED LOGOUT #{@curb_instance.url}: HTTP #{@curb_instance.response_code}"
        @curb_instance = nil
      end
      self
    end
    
    private
    def login(options = {})
      @curb_instance.url = 'https://www.google.com/accounts/ServiceLoginAuth'
      @curb_instance.perform
      # If String#force_encoding doesn't exist we are on Ruby 1.8 and we shouldn't encode anything
      @curb_instance.body_str.force_encoding("UTF-8") if @curb_instance.body_str.respond_to?(:force_encoding)
      
      defeat_google_xsrf(@curb_instance.body_str)
      
      begin
        fields = [ PostField.content('continue', (options[:continue_url] || 'https://www.google.com/voice')),
                   PostField.content('GALX', @galx),
                   PostField.content('service', (options[:google_service] || 'grandcentral')),
                   PostField.content('Email', options[:google_account_email]),
                   PostField.content('Passwd', options[:google_account_password]) ]
      rescue ArgumentError
        warn "Unable to log in."
        raise GvoiceRuby::LoginFailed
      end
      options.merge!({ :post_url => 'https://www.google.com/accounts/ServiceLoginAuth' })
      
      post(options, fields)
    end
    
    def post(options, fields)
      @curb_instance.url = options[:post_url] #"https://www.google.com/voice/call/connect || https://www.google.com/voice/sms/send"
      @curb_instance.http_post(fields)
      
      logger.info "FINISHED POST TO #{options[:post_url]}: HTTP #{@curb_instance.response_code}"
      return @curb_instance
    end
    
    def fetch_page(url = 'https://www.google.com/voice/inbox/recent')
  
      @curb_instance.url = url #"https://www.google.com/voice/inbox/recent"
      
      @curb_instance.http_get
      
      logger.info "FINISHED FETCHING #{url}: HTTP #{@curb_instance.response_code}"
      return @curb_instance
    end
    
    def get_unread_counts(inbox)
      @unread_counts = inbox['unreadCounts']
      @any_unread = inbox['unreadCounts']['unread'].to_i != 0
      logger.info "No unread messages in your Google Voice inbox." unless @any_unread
    end
    
    def defeat_google_xsrf(body_string)
      # defeat Google's XSRF protection
      doc = Nokogiri::HTML::DocumentFragment.parse(body_string)
      doc.css('div.loginBox table#gaia_table input').each do |input|
        if input.to_s =~ /GALX/u
          @galx = input.to_s.scan(/value\="(.+?)"/u).flatten!.pop
        else
          next
          # raise IOError, 'Cannot fetch galx attribute from Google.'
        end
      end
    end
    
    def set_rnr_se_token
      if @curb_instance.response_code == 200 #&& @curb_instance.respond_to?(:perform) # Vestigial?
        @curb_instance.url = "http://www.google.com/voice"
        @curb_instance.perform 
        @_rnr_se = extract_rnr_se(@curb_instance.body_str)
      else
        raise IOError, "Curb instance was not properly initialized."  
      end
    end
    
    def extract_rnr_se(body_string)
      begin
        /value="(.+)"/.match(Nokogiri::HTML::Document.parse(body_string).css('form#gc-search-form').inner_html)
        return $1
      rescue IOError
        raise IOError, "Problem extracting _rnr_se code from page."
      end
    end
    
    def initialize_curb
      @curb_instance = Easy.new do |curl|
        # Google gets mad if you don't fake this...
        curl.headers["User-Agent"] = "Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10.5; en-US; rv:1.9.1.2) Gecko/20090729 Firefox/3.5.2"
        # Let's see what happens under the hood
        # curl.verbose = true

        # Google will redirect us a bit
        curl.follow_location = true

        # Google will make sure we retain cookies
        curl.enable_cookies = true
      end
    end
  end
end
