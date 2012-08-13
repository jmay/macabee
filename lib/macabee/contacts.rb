# Macabee::Contacts is ruby representation of Mac Address Book

require "appscript"

class Macabee::Contacts
  attr_reader :ab #, :contacts, :groups

  # suck all the contacts from local MacOSX Address Book into a single array
  def initialize
    @ab = Appscript.app("Address Book")
  end

  def ref(ab_id)
    begin
      case ab_id
      when /ABPerson/
        @ab.people.ID(ab_id).get
      when /ABGroup/
        @ab.groups.ID(ab_id).get
      else
        nil
      end
    rescue Appscript::CommandError
      nil
    end
  end

  def fetch(ab_id)
    rec = ref(ab_id)
    if rec
      case ab_id
      when /ABPerson/
        Macabee::Contact.new(rec)
      when /ABGroup/
        Macabee::Group.new(rec)
      end
    end
  end

  def contacts
    @ab.people.get.map {|abperson| Macabee::Contact.new(abperson)}
  end

  def groups
    @ab.groups.get.map {|abgroup| Macabee::Group.new(abgroup)}
  end

  # def all
  #   @contacts ||= load_contacts
  #   @groups ||= load_groups
  # end

  def to_hash
    {
      'contacts' => contacts.map(&:to_hash),
      'groups' => groups.map(&:to_hash)
    }
  end
end
