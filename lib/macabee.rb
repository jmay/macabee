unless Kernel.respond_to?(:require_relative)
  module Kernel
    def require_relative(path)
      require File.join(File.dirname(caller[0]), path.to_str)
    end
  end
end

framework 'AddressBook'

require_relative "macabee/version"
require_relative "macabee/contact"
require_relative "macabee/group"
require_relative "macabee/contacts"
