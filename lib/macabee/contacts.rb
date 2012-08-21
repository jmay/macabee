# Macabee::Contacts is ruby representation of Mac Address Book

class Macabee::Contacts
  attr_reader :ab #, :contacts, :groups

  # suck all the contacts from local MacOSX Address Book into a single array
  def initialize
    @ab = ABAddressBook.addressBook
  end

  def ref(ab_id)
    query = ABPerson.searchElementForProperty('com.apple.uuid',
                    label:nil, key:nil, value: ab_id,
                    comparison:KABEqual)
    ab.recordsMatchingSearchElement(query).first
  end

  def fetch(ab_id)
    rec = ref(ab_id)
    if rec
      # case ab_id
      # when /ABPerson/
        Macabee::Contact.new(rec)
      # when /ABGroup/
      #   Macabee::Group.new(rec)
      # end
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
