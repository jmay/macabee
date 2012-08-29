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

  def lookup(*args)
    case args.count
    when 2
      firstname, lastname = args
    when 1
      d = args.first
      firstname = d['name'] && d['name']['first']
      lastname = d['name'] && d['name']['last']
    end

    q1 = ABPerson.searchElementForProperty(KABFirstNameProperty,
                    label:nil, key:nil, value: firstname,
                    comparison:KABEqual)
    q2 = ABPerson.searchElementForProperty(KABLastNameProperty,
                    label:nil, key:nil, value: lastname,
                    comparison:KABEqual)
    query = ABSearchElement.searchElementForConjunction(KABSearchAnd, children: [q1, q2])
    matches = ab.recordsMatchingSearchElement(query)
    if matches.count == 1
      rec = matches.first
      Macabee::Contact.new(rec)
    else
      # return nothing if there are no matches, or many
      # TODO: figure out better multi-match handling; any reliable way to guess which one we want?
      nil
    end
  end

  def group(ab_id)
    query = ABGroup.searchElementForProperty(KABUIDProperty,
                    label:nil, key:nil, value: ab_id,
                    comparison:KABEqual)
    if rec = ab.recordsMatchingSearchElement(query).first
      Macabee::Group.new(rec)
    end
  end

  def group_lookup(name)
    query = ABGroup.searchElementForProperty(KABNameProperty,
                    label:nil, key:nil, value: name,
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
      # no existing record, so this is an add
      contact = Macabee::Contact.new
    end
    contact.compare(hash)
  end

  def diffs(contactlist)
    contactlist.each_with_object({}) do |data, changes|
      external_uid = data['xref']['novum']
      case data['xref']['ab']
      when nil
        # Any record that doesn't have a local AB identifier has never been sychronized with this
        # AB database. Check to see if a matching record exists that we can coalesce with.
        if contact = lookup(data)
          # found one
          already_known = (contactlist - [contact]).find {|c| (c['xref'] && c['xref']['ab']) == contact.uuid}
          if !already_known
            changeset = contact.reverse_compare(data)
            changes[external_uid] = changeset
          end
        end
        # If there's no record in AB, that's fine, when we are ready to do an update we will
        # treat that as an addition and create a new ABPerson. Nothing to emit here.

      when 'DELETED'
        # If the identifier says 'DELETED' then we don't want to look for it in AB; we might
        # want to retain locally-deleted entries in our source, but we don't want to try to
        # reconstitute them in AB.

      else # this looks like a record that we've already synchronized with
        contact = find(data)
        if !contact
          # That KABUIDProperty value no longer appears. Maybe the UIDs were rebuilt? (That can happen
          # when you resync with iCloud.) Look for a record with the same name.
          contact = lookup(data)
          # do I need to repeat the already-known check above?
        end

        if contact
          changeset = contact.reverse_compare(data)
          if changeset.any?
            # there have been changes
            changes[external_uid] = changeset
          end
          # if there are no changes, emit nothing for this record
        else
          # This contact does not appear in the target, assume it has been deleted.
          # Construct a changeset that will reflect that back onto the source data.
          changes[external_uid] = [
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
    if contactlist.select {|r| !r['xref'] || !r['xref']['novum']}.any?
      raise "At least one record is missing an xref.novum value"
    end
    diffs(contactlist)
    # additions(contactlist).merge(diffs(contactlist))
  end

end
