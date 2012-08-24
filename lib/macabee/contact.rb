# Macabee::Contact is ruby representation of a single MacOSX Address Book entry

# require "hashdiff"
require "treet"

class Macabee::Contact
  attr_reader :person

  ContactKeys = %w(name business other associates xref phones addresses emails links)

  PropertyMappings = {
    'name.first' => KABFirstNameProperty,
    'name.middle' => KABMiddleNameProperty,
    'name.last' => KABLastNameProperty,
    'name.suffix' => KABSuffixProperty,
    'name.nick' => KABNicknameProperty,
    'name.title' => KABTitleProperty,

    'business.organization' => KABOrganizationProperty,
    'business.job_title' => KABJobTitleProperty,
    'business.department' => KABDepartmentProperty,

    'other.note' => KABNoteProperty,
    'other.dob' => KABBirthdayProperty,

    'phones' => [KABPhoneProperty, 'phone'],
    'emails' => [KABEmailProperty, 'email'],
    'addresses' => [KABAddressProperty, :to_ab_address],
    # 'links' => THIS IS SPECIAL

    # 'address[]' => 'address[].label',
    # 'address[].street' => 'address[].street',

    # 'phones' => :phone,
    # 'emails' => :email
  }

  @@mappings = {
    'name.first' => :first_name,
    'name.middle' => :middle_name,
    'name.last' => :last_name,
    'name.suffix' => :suffix,

    'business.job_title' => :job_title,
    'business.organization' => :organization,
    'business.company' => :company,

    'other.note' => :note,

    'address[]' => 'address[].label',
    'address[].street' => 'address[].street',

    'phones' => :phone,
    'emails' => :email
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

  def self.compare(h1, h2)
    Treet::Hash.diff(h1, h2)
  end

  def compare(target_hash)
    Macabee::Contact.compare(to_hash, target_hash)
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

          if keyname == 'xref.ab'
            puts "*** DO NOT APPLY CHANGES TO UID VALUE ***"
          else
            puts "MAP #{keyname} TO #{property} AND SET TO #{v2}"
            set(property, v2)
          end

        when '+'
          # add something
          if is_array
            puts "MAP #{keyname} TO MULTIVALUE #{property} and ADD #{v1}"
            addmulti(property.first, v1, property.last)
          else
            puts "MAP #{keyname} TO #{property} AND SET TO #{v1}"
            set(property, v1)
          end

        when '-'
          # remove something
          if is_array
            puts "MAP #{keyname} to MULTIVALUE and REMOVE INDEX #{index.to_i}"
            delmulti(property.first, index.to_i)
          else
            puts "MAP #{keyname} TO #{property} AND DELETE"
            set(property, nil)
          end
        end
      else
        raise "NO PROPERTY MAPPING FOR KEY #{keyname}"
      end
    end
  end

  def patch(diffs)
    diffs.each do |k,diff|
      case diff
      when Array
        # if diff.empty?
        #   puts "No changes for #{k}"
        # end
        diff.each do |action,field,v1,v2|
          abfield = @@mappings["#{k}.#{field}"]
          raise "unmapped field #{k}" unless abfield

          case action
          when '~' # replace
            puts "person.#{abfield}.set('#{v2}')"
            person.send(abfield).set(v2)

          when '+' # add
            puts "person.#{abfield}.set('#{v1}')"
            person.send(abfield).set(v1)

          when '-' # delete
            puts "person.#{abfield}.delete"
            person.send(abfield).delete

          else
            raise "unknown action [#{diff}] for #{k}"
          end
        end

      when Hash
        abfield = @@mappings[k]
        case k
        when 'phones', 'emails'
          diff[:deletes].each do |index|
            puts "person.send(#{k}).get[#{index}].delete"
            person.send(k).get[index].delete
          end
          diff[:adds].each do |hash|
            data = self.send("to_#{abfield}", hash)
            puts "ab.make(:new => :#{abfield}, :at => #{person}, :with_properties => #{data.inspect}"
            person.make(:new => abfield.to_sym, :at => person, :with_properties => data)
          end

        when 'links'
          # figure out what type of object this is (url, social profile, im handle) and Do The Right Thing

          diff[:deletes].each do |index|
            delete_link(transformed['links'][index])
          end
          diff[:adds].each do |hash|
            meth = linktype(hash)
            data = self.send("to_#{meth}", hash)
            puts "ab.make(:new => :#{meth}, :at => #{person}, :with_properties => #{data.inspect}"
            person.make(:new => meth.to_sym, :at => person, :with_properties => data)
          end

          # if diff[:deletes].any? || diff[:adds].any?
          #   raise "links are not supported yet"
          # end

        else
          raise "unmapped field #{k}"
        end

      else
        raise "cannot apply diff #{diff.inspect} for #{k}"
      end

    end
    puts "person.save"
    person.save

  end

  # transform an individual contact to our standard structure
  def transform
    {
      'name' => names,
      'business' => business,
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
    get(KABUIDProperty)
  end

  def xref
    {
      # 'ab' => get('com.apple.uuid')
      'ab' => uuid
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

  def business
    {
      'organization' => get(KABOrganizationProperty),
      'job_title' => get(KABJobTitleProperty),
      'department' => get(KABDepartmentProperty)
    }.reject {|k,v| v.nil?}
  end

  def other_data
    {
      'dob' => get(KABBirthdayProperty),
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
        'service' => h['InstantMessageService'],
        'handle' => h['InstantMessageUsername']
      }.reject {|k,v| v.nil? || v.empty? || v == 'None'}
    end
  end


  def linktype(hash)
    if hash['handle'] && hash['service'] && !hash['url']
      "#{hash['service']}_handle"
    elsif hash['service']
      'social_profile'
    else
      'url'
    end
  end

  def delete_link(hash)
    meth = linktype(hash)
    puts "Using #{meth} for #{hash.inspect}"
    case meth
    when /handle/
      handles = person.send("#{meth}s").get.to_a
      this_index = handles.index {|h| (h.label.get == hash['label']) && (h.value.get == hash['handle'])}

      puts "person.send(:#{meth}s).get[#{this_index}].delete #{hash.inspect}"
      person.send("#{meth}s").get[this_index].delete

    when /url/
      urls = person.urls.get.to_a
      this_index = urls.index {|h| (h.label.get == hash['label']) && (h.value.get == hash['url'])}

      puts "person.send(:#{meth}s).get[#{this_index}].delete #{hash.inspect}"
      person.urls.get[this_index].delete

    when /social_profile/
      this_index = social_profiles.index {|h| h == hash}
      # profiles = person.social_profiles.get.to_a
      # this_index = profiles.index {|h| (h.service_name.get == hash['service']) && (h.url.get == (hash['url'] || :missing_value)) && (h.user_name.get == (hash['handle'] || :missing_value))}
      raise "Cannot find profile to delete for #{hash}" if this_index.nil?

      puts "person.social_profiles.get[#{this_index}].delete #{hash}"

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

  def to_url(hash)
    {
      :label => hash['label'],
      :value => hash['url']
    }
  end

  def to_social_profile(hash)
    {
      :service_name => hash['service'],
      :user_name => hash['handle'],
      :url => hash['url']
    }.reject {|k,v| v.nil?}
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

  private

  def get(property)
    person.valueForProperty(property)
  end

  def set(property, value)
    person.setValue(value, forProperty: property)
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
      send(keyname, hash)
    else
      raise "Don't know what to do with #{keyname.class} for #{property} #{hash}"
    end

    multi.addValue(value, withLabel: hash['label'])
    set(property, multi)
  end

  def delmulti(property, index)
    multi = get(property).mutableCopy
    multi.removeValueAndLabelAtIndex(index)
    set(property, multi)
  end
end
