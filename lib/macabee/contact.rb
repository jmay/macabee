# Macabee::Contact is ruby representation of a single MacOSX Address Book entry

require "treet"

class Macabee::Contact
  attr_reader :person

  ContactKeys = %w(name org other associates xref phones addresses emails links)

  PropertyMappings = {
    'name.first' => KABFirstNameProperty,
    'name.middle' => KABMiddleNameProperty,
    'name.last' => KABLastNameProperty,
    'name.suffix' => KABSuffixProperty,
    'name.nick' => KABNicknameProperty,
    'name.title' => KABTitleProperty,

    'org.organization' => KABOrganizationProperty,
    'org.job_title' => KABJobTitleProperty,
    'org.department' => KABDepartmentProperty,
    'org.is_org' => KABPersonFlags,

    'other.note' => KABNoteProperty,
    'other.dob' => KABBirthdayProperty,

    'phones' => [KABPhoneProperty, 'phone'],
    'emails' => [KABEmailProperty, 'email'],
    'addresses' => [KABAddressProperty, :to_ab_address],
    'links' => []
    # 'links' => THIS IS SPECIAL

    # 'address[]' => 'address[].label',
    # 'address[].street' => 'address[].street',

    # 'phones' => :phone,
    # 'emails' => :email
  }


  # suck all the contacts from local MacOSX Address Book into a single array
  def initialize(person)
    @person = person
  end

  def transformed
    @transformed ||= transform
  end

  def to_hash
    transformed
  end

  def to_s
    h = to_hash
    "#{h['xref']['ab']}: #{h['name']['first']} #{h['name']['last']}"
  end


  def self.compare(h1, h2)
    Treet::Hash.diff(h1, h2)
  end

  def compare(target_hash)
    Macabee::Contact.compare(to_hash, target_hash)
  end

  def reverse_compare(target_hash)
    # ignore any xref values in the comparison data except for any AB value
    target_hash['xref'] = {
      'ab' => target_hash['xref']['ab']
    }

    Macabee::Contact.compare(target_hash, to_hash)
  end

  # WARNING: `#apply` only *stages* the changes to the ABPerson record.
  # In order to persist those changes to the database, you must call `#save` on the ABAddressBook object!
  def apply(diffs)
    diffs.each do |diff|
      flag, key, v1, v2 = diff
      if key =~ /\[/
        keyname, is_array, index = key.match(/^(.*)(\[)(.*)\]$/).captures
      else
        keyname = key
      end

      property = PropertyMappings[keyname]
      if property
        case flag
        when '~'
          # change a value in place

          if keyname == 'other.dob'
            # date-of-birth must be formatted correctly
            dob = v1 && Date.parse(v1).to_time
            set(property, dob)

          elsif keyname == 'org.is_org'
            # must merge with other flags
            set_org(property, v1)

          elsif keyname == 'other.note'
            # for notes, we concatenate, not replace
            newnote = [v1, v2].join("\n\n")
            set(property, newnote)

          elsif is_array
            raise "SOMETHING IS WRONG - NOT SUPPOSED TO EVER CHANGE ARRAY ENTRIES IN PLACE, ALWAYS DELETE & ADD"

          else
            # puts "MAP #{keyname} TO #{property} AND SET TO #{v1}"
            set(property, v1)
          end

        when '+'
          # add something
          if keyname == 'other.dob'
            # date-of-birth must be formatted correctly
            dob = v1 && Date.parse(v1).to_time
            set(property, dob)
          elsif keyname == 'org.is_org'
            # must merge with other flags
            set_org(property, v1)
          elsif is_array
            # multivalue property
            if property == []
              add_link(v1)
            else
              addmulti(property.first, v1, property.last)
            end
          else
            # scalar property
            set(property, v1)
          end

        when '-'
          # remove something
          if is_array
            # multivalue property
            if property == []
              del_link(index.to_i, v1)
            else
              delmulti(property.first, index.to_i)
            end
          else
            # scalar property
            if keyname == 'org.is_org'
              # must clear a flag bit, not wipe the entire flag
              set_org(property, 0)
            else
              # set the value to nil
              set(property, nil)
            end
          end
        end
      else
        if keyname == 'xref.ab'
          raise "*** DO NOT APPLY CHANGES TO UID VALUE ***"
        else
          raise "NO PROPERTY MAPPING FOR KEY #{keyname}"
        end
      end
    end
  end

  # transform an individual contact to our standard structure
  def transform
    {
      'name' => names,
      'org' => org,
      'other' => other_data,
      'associates' => associates,
      'xref' => xref,

      # these are lists with zero or more members; duplicates allowed; member order is arbitrary (so we pick
      # a standardized order for list comparison purposes)
      'phones' => phones,
      'addresses' => addresses,
      'emails' => emails,
      'links' => links
    }.reject {|k,v| v.nil? || v.empty?}
  end

  def uuid
    to_hash['xref'] && to_hash['xref']['ab']
  end

  # KABUIDProperty appears to be generated by the framework when a new record is created.
  # The `com.apple.uuid` property seems to exist only for records that are synced with iCloud.
  # WARNING: KABUIDProperty is not permanent; the framework will destroy and recreate this
  # value when iCloud syncing is turned off & on.
  def lookup_uuid
    get(KABUIDProperty)
  end

  def xref
    {
      'ab' => lookup_uuid
    }
  end

  def names
    {
      # 'full' => # full name field is generated on MacOSX from first+middle+last+suffix; no API to get it
      'first' => get(KABFirstNameProperty),
      'middle' => get(KABMiddleNameProperty),
      'last' => get(KABLastNameProperty),
      'title' => get(KABTitleProperty),
      'suffix' => get(KABSuffixProperty),
      'nick' => get(KABNicknameProperty)
    }.reject {|k,v| v.nil?}
  end

  def org
    {
      'organization' => get(KABOrganizationProperty),
      'job_title' => get(KABJobTitleProperty),
      'department' => get(KABDepartmentProperty),
      'is_org' => (get(KABPersonFlags) & 01 == 1)
    }.reject {|k,v| !v} # only nil and false evaluate to false
  end

  def other_data
    {
      'dob' => (dob = get(KABBirthdayProperty)) && dob.to_date.to_s,
      'note' => get(KABNoteProperty)
    }.reject {|k,v| v.nil?}
  end

  def associates
    multi = get(KABRelatedNamesProperty)
    multi && multi.count.times.map do |i|
      {
        'label' => ABPerson.ABCopyLocalizedPropertyOrLabel(multi.labelAtIndex(i)),
        'name' => multi.valueAtIndex(i)
      }
    end
  end

  def phones
    multi = get(KABPhoneProperty)
    multi && multi.count.times.map do |i|
      {
        'label' => ABPerson.ABCopyLocalizedPropertyOrLabel(multi.labelAtIndex(i)),
        'phone' => multi.valueAtIndex(i)
      }
    end
  end

  def addresses
    multi = get(KABAddressProperty)
    multi && multi.count.times.map do |i|
      h = multi.valueAtIndex(i)
      {
        'label' => ABPerson.ABCopyLocalizedPropertyOrLabel(multi.labelAtIndex(i)),
        'street' => h[KABAddressStreetKey],
        'city' => h[KABAddressCityKey],
        'state' => h[KABAddressStateKey],
        'postalcode' => h[KABAddressZIPKey],
        'country' => h[KABAddressCountryKey]
      }.reject {|k,v| v.nil? || v.empty?}
    end
  end

  def emails
    multi = get(KABEmailProperty)
    multi && multi.count.times.map do |i|
      {
        'label' => ABPerson.ABCopyLocalizedPropertyOrLabel(multi.labelAtIndex(i)),
        'email' => multi.valueAtIndex(i)
      }
    end
  end

  def links
    (urls||[]) + (social_profiles||[]) + (im_handles||[])
  end

  def urls
    multi = get(KABURLsProperty)
    multi && multi.count.times.map do |i|
      {
        'label' => ABPerson.ABCopyLocalizedPropertyOrLabel(multi.labelAtIndex(i)),
        'url' => multi.valueAtIndex(i)
      }
    end
  end

  def social_profiles
    multi = get(KABSocialProfileProperty)
    multi && multi.count.times.map do |i|
      h = multi.valueAtIndex(i)
      {
        'label' => multi.labelAtIndex(i) && ABPerson.ABCopyLocalizedPropertyOrLabel(multi.labelAtIndex(i)),
        'service' => h['serviceName'],
        'url' => h['url']
      }.reject {|k,v| v.nil? || v.empty? || v == 'None'}
    end
  end

  def im_handles
    multi = get(KABInstantMessageProperty)
    multi && multi.count.times.map do |i|
      h = multi.valueAtIndex(i)
      {
        'label' => ABPerson.ABCopyLocalizedPropertyOrLabel(multi.labelAtIndex(i)),
        'service' => ABPerson.ABCopyLocalizedPropertyOrLabel(h['InstantMessageService']),
        'handle' => h['InstantMessageUsername']
      }.reject {|k,v| v.nil? || v.empty? || v == 'None'}
    end
  end

  # determine what slot in the Address Book taxonomy a particular link belongs to:
  # * instant messaging accounts (KABInstantMessageProperty) have a handle but no URL; optionally a service
  # * social profiles (KABSocialProfileProperty) have a service and either handle or URL
  # * urls (KABURLsProperty) have ONLY a url, no service
  # Social profiles take precedence over IM accounts.
  # Output is the AB property key and the value prepared for storing with hash keys renamed for AB.
  def classify(hash)
    if hash['handle'] && !hash['url']
      KABInstantMessageProperty
    elsif hash['service']
      KABSocialProfileProperty
    elsif hash['url']
      KABURLsProperty
    else
      raise "I can't recognize this link data: #{hash}"
    end
  end

  def delete_link(hash)
    meth = linktype(hash)
    # puts "Using #{meth} for #{hash.inspect}"
    case meth
    when /handle/
      handles = person.send("#{meth}s").get.to_a
      this_index = handles.index {|h| (h.label.get == hash['label']) && (h.value.get == hash['handle'])}

      # puts "person.send(:#{meth}s).get[#{this_index}].delete #{hash.inspect}"
      person.send("#{meth}s").get[this_index].delete

    when /url/
      urls = person.urls.get.to_a
      this_index = urls.index {|h| (h.label.get == hash['label']) && (h.value.get == hash['url'])}

      # puts "person.send(:#{meth}s).get[#{this_index}].delete #{hash.inspect}"
      person.urls.get[this_index].delete

    when /social_profile/
      this_index = social_profiles.index {|h| h == hash}
      # profiles = person.social_profiles.get.to_a
      # this_index = profiles.index {|h| (h.service_name.get == hash['service']) && (h.url.get == (hash['url'] || :missing_value)) && (h.user_name.get == (hash['handle'] || :missing_value))}
      raise "Cannot find profile to delete for #{hash}" if this_index.nil?

      # puts "person.social_profiles.get[#{this_index}].delete #{hash}"

      # some sort of bug with deleting social profiles
      # http://macscripter.net/viewtopic.php?id=38956&p=2
      # can't do this: person.social_profiles.get[this_index].delete
      # the following workaround appears to result in the profile entry being removed:
      profile = person.social_profiles.get[this_index]
      profile.user_name.delete
      profile.url.delete
      profile.save

    else
      raise "Don't know what #{meth} is"
    end
  end

  def to_ab_address(h)
    {
      KABAddressStreetKey => h['street'],
      KABAddressCityKey => h['city'],
      KABAddressStateKey => h['state'],
      KABAddressZIPKey => h['postalcode'],
      KABAddressCountryKey => h['country']
    }
  end

  def to_ab_url
    # not needed, this is a standard labeled multi-value string list
  end

  def to_ab_im_handle(h)
    {
      'InstantMessageService' => h['service'],
      'InstantMessageUsername' => h['handle']
    }
  end

  def to_ab_social_profile(hash)
    {
      'serviceName' => hash['service'],
      'username' => hash['handle'],
      'url' => hash['url']
    }.reject {|k,v| v.nil?}
  end


  # private

  def get(property)
    person.valueForProperty(property)
  end

  def set(property, value)
    person.setValue(value, forProperty: property)
  end

  def set_org(property, bool)
    current_value = get(property)
    new_value = current_value ^ (bool ? 1 : 0)
    set(property, new_value)
  end

  def addmulti(property, hash, rule)
    staticvalue = get(property) # this is a ABMultiValueCoreDataWrapper, can't alter it
    multi = staticvalue ? staticvalue.mutableCopy : ABMutableMultiValue.new

    # if keyname is blank, the value is the entire hash
    # (it's a kABMultiDictionaryProperty like for kABAddressProperty)
    value = case rule
    when String
      # a single value for each entry in the MultiValue list, this says where to get it from the hash
      hash[rule]
    when Symbol
      # a hash/dictionary for each entry in the MultiValue list, this says how to convert it
      # field names must be what Address Book expects, or it will reject the entry silently
      send(rule, hash)
    else
      raise "Don't know what to do with #{keyname.class} for #{property} #{hash}"
    end

    multi.addValue(value, withLabel: hash['label'] || '')
    set(property, multi)
  end

  def add_link(valueToInsert)
    property = classify(valueToInsert)
    formattedHash = case property
    when KABURLsProperty
      addmulti(property, to_ab_url(valueToInsert), 'url')
    when KABSocialProfileProperty
      addmulti(property, valueToInsert, :to_ab_social_profile)
    when KABInstantMessageProperty
      addmulti(property, valueToInsert, :to_ab_im_handle)
    else
      raise "Ouch!"
    end
  end

  def delmulti(property, index)
    multi = get(property).mutableCopy
    multi.removeValueAndLabelAtIndex(index)
    set(property, multi)
  end

  def del_link(i, valueToDelete)
    property, hash = classify(valueToDelete)

    current = case property
    when KABURLsProperty
      urls
    when KABSocialProfileProperty
      social_profiles
    when KABInstantMessageProperty
      im_handles
    else
      raise "Ouch!"
    end
    puts current
    if pos = current.index(valueToDelete)
      delmulti(property, pos)
    else
      puts "NO MATCH FOUND FOR #{valueToDelete}"
    end
  end
end
