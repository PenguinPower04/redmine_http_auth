module HTTPAuthPatch
  def self.included(base)
    base.send(:include, ClassMethods)
    base.class_eval do
      #avoid infinite recursion in development mode on subsequent requests
      alias_method :find_current_user,
        :find_current_user_without_httpauth if method_defined? 'find_current_user_without_httpauth'
      #chain our version of find_current_user implementation into redmine core
      alias_method_chain(:find_current_user, :httpauth)
    end
  end

  module ClassMethods
    def find_current_user_with_httpauth
      #first proceed with redmine's version of finding current user
      user = find_current_user_without_httpauth
      #if the http_auth is disabled in config, return the user
      return user unless Setting.plugin_http_auth['enable'] == "true"

      remote_username = request.env[Setting.plugin_http_auth['server_env_var']]
      if remote_username.nil?
        #do not touch user, if he didn't use http authentication to log in
        return user unless used_http_authentication?
        #log out previously authenticated user
        reset_session
        return nil
      end

      #return if the user has not been changed behind the session
      return user unless session_changed? user, remote_username

      #log out current logged in user
      reset_session
      try_login remote_username
    end

    def try_login(remote_username)
      #find user by login name or email address
      if use_email?
        user = User.active.find_by_mail remote_username
      else
        user = User.active.find_by_login remote_username
      end
      #login and return user if user was found
      do_login user unless user.nil?
    end

    def used_http_authentication?
      session[:http_authentication] == true
    end

    def use_email?
      Setting.plugin_http_auth['lookup_mode'] == 'email'
    end

    def session_changed?(user, remote_username)
      if user.nil?
        true
      else
        use_email? ? user.mail != remote_username : user.login != remote_username
      end
    end

    def do_login(user)
      if (user && user.is_a?(User))
        session[:user_id] = user.id
        session[:http_authentication] = true
        User.current = user
      end
    end
  end
end

