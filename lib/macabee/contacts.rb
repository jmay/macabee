# Macabee::Contacts is ruby representation of Mac Address Book

class Macabee::Contacts
  attr_reader :ab

  def initialize
    # Apple docs recommend using `addressBook`, not `sharedAddressBook`
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

  # suck all the contacts from local MacOSX Address Book into a single array
  def contacts
    @contacts ||= @ab.people.map {|abperson| Macabee::Contact.new(abperson)}
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

  def contacts_indexed
    @contacts_indexed ||= contacts.each_with_object({}) do |contact, hash|
      hash[contact.uuid] = contact
    end
  end

  def find(hash)
    abid = hash['xref']['ab']
    contact = contact(abid)
    if contact.nil?
      contact = lookup(hash['name']['first'], hash['name']['last'])
      # if this finds a match, then the local Address Book UUID has changed
    end
    contact
  end

  def diff(hash)
    contact = find(hash)
    if contact.nil?
      raise "Unable to find matching contact record."
    end
    contact.compare(hash)
  end

  def diffs(contactlist)
    contactlist.each_with_object({}) do |data, changes|
      if data['xref'] && data['xref']['ab'] != 'DELETED'
        # Any record that doesn't have an AB identifier is new, so should be ignore here
        # when looking for AB changes that need to go back.
        # If the identifier says 'DELETED' then we don't want to look for it in AB; we might
        # want to retain locally-deleted entries in our source, but we don't want to try to
        # reconstitute them in AB.

        contact = find(data)
        if contact
          changeset = contact.compare(data)
          if changeset.any?
            # there have been changes
            changes[contact.uuid] = changeset
          end
          # if there are no changes, emit nothing for this record
        else
          # This contact does not appear in the target, assume it has been deleted.
          # Construct a changeset that will reflect that back onto the source data.
          old_uid = data['xref']['ab']
          changes[old_uid] = [
            [
              '~',
              'xref.ab',
              'DELETED',
              data['xref']['ab']
            ]
          ]
        end
      end
    end
  end

  def apply(hash)
    contact = find(hash)
    diffs = contact.compare(hash)
    contact.apply(diffs)
    contact
  end

  # persist any staged contact changes to the database
  def save!
    @ab.save
  end

  def additions(contactlist)
    newkeys = contacts_indexed.keys - contactlist.map{|c| c['xref'] && c['xref']['ab']}
    newkeys.each_with_object({}) {|k, hash| hash[k] = contacts_indexed[k].to_hash}
  end

  # collection of record changes describing AB data state that doesn't match the inbound source records
  def revise(contactlist)
    additions(contactlist).merge(diffs(contactlist))
  end

end
