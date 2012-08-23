unless Kernel.respond_to?(:require_relative)
  module Kernel
    def require_relative(path)
      require File.join(File.dirname(caller[0]), path.to_str)
    end
  end
end

require "macabee/version"

framework 'AddressBook'

require "macabee/util"

require "macabee/contact"
require "macabee/group"
require "macabee/contacts"

module Macabee
  # Your code goes here...
end
