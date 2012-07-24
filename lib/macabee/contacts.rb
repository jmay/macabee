# Macabee::Contacts is ruby representation of Mac Address Book

require "appscript"

class Macabee::Contacts
  attr_reader :ab, :contacts

  # suck all the contacts from local MacOSX Address Book into a single array
  def initialize
    @ab = Appscript.app("Address Book")
  end

  def ref(ab_id)
    begin
      @ab.people.ID(ab_id).get
    rescue Appscript::CommandError
      nil
    end
  end
  def fetch(ab_id)
    (rec = ref(ab_id)) && Macabee::Contact.new(rec)
  end

  def all
    @contacts ||= @ab.people.get.map {|abperson| Macabee::Contact(abperson)}
  end
end
