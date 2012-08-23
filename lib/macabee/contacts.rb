# Macabee::Contacts is ruby representation of Mac Address Book

class Macabee::Contacts
  attr_reader :ab

  # suck all the contacts from local MacOSX Address Book into a single array
  def initialize
    @ab = ABAddressBook.addressBook
  end

  def contact(ab_id)
    query = ABPerson.searchElementForProperty(KABUIDProperty,
                    label:nil, key:nil, value: ab_id,
                    comparison:KABEqual)
    if rec = ab.recordsMatchingSearchElement(query).first
      Macabee::Contact.new(rec)
    end
  end

  def lookup(firstname, lastname)
    q1 = ABPerson.searchElementForProperty(KABFirstNameProperty,
                    label:nil, key:nil, value: firstname,
                    comparison:KABEqual)
    q2 = ABPerson.searchElementForProperty(KABLastNameProperty,
                    label:nil, key:nil, value: lastname,
                    comparison:KABEqual)
    query = ABSearchElement.searchElementForConjunction(KABSearchAnd, children: [q1, q2])
    if rec = ab.recordsMatchingSearchElement(query).first
      Macabee::Contact.new(rec)
    end
  end

  def group(ab_id)
    query = ABGroup.searchElementForProperty('com.apple.uuid',
                    label:nil, key:nil, value: ab_id,
                    comparison:KABEqual)
    if rec = ab.recordsMatchingSearchElement(query).first
      Macabee::Group.new(rec)
    end
  end

  def contacts
    @ab.people.map {|abperson| Macabee::Contact.new(abperson)}
  end

  def groups
    @ab.groups.map {|abgroup| Macabee::Group.new(abgroup)}
  end

  def to_hash
    {
      'contacts' => contacts.map(&:to_hash),
      'groups' => groups.map(&:to_hash)
    }
  end
end
