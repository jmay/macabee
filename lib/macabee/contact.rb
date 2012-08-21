# Macabee::Contact is ruby representation of a single MacOSX Address Book entry

# require "active_support/core_ext" # something in multi_json breaks with MacRuby (strings come out blank)
require "andand"
require "hashdiff"

class Macabee::Contact
  attr_reader :person


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

  def compare(target_hash)
    # construct a diff that would transform the current record into the new hash
    # should the inbound data contain the xref stuff? probably, because there might be xrefs from other sources;
    # but the xrefs shouldn't be part of the comparison and shouldn't be stored back to the AB record.
    # puts "COMPARING..."
    # puts JSON.pretty_generate(transformed)
    # puts "...TO..."
    # puts JSON.pretty_generate(target_hash)

    # HashDiff.diff(transformed, target_hash)

    %w(name business other phones emails links).each_with_object({}) do |k,diffs|
      diffs[k] = case transformed[k] || []
      when Hash
        HashDiff.diff(transformed[k], target_hash[k])
        # transformed[k].diff(target_hash[k])
      when Array
        Macabee::Util.hasharraydiff(transformed[k] || [], target_hash[k])
      else
        raise "can't deal with #{k} in #{transformed.inspect}"
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
    # base_properties = person.properties_.get.select {|k,v| v != :missing_value && ![:class_, :vcard, :selected, :image].include?(k)}

    names = {
      # 'full' => props['name'], # full name field is generated on MacOSX from first+middle+last+suffix
      'first' => person.valueForProperty(KABFirstNameProperty),
      'middle' => person.valueForProperty(KABMiddleNameProperty),
      'last' => person.valueForProperty(KABLastNameProperty),
      'suffix' => person.valueForProperty(KABSuffixProperty)
    }.reject {|k,v| v.nil?}.dup

    business = {
      'organization' => person.valueForProperty(KABOrganizationProperty),
      'job_title' => person.valueForProperty(KABTitleProperty)
    }.reject {|k,v| v.nil?}

    other = {
      'birth_date' => person.valueForProperty(KABBirthdayProperty),
      'note' => person.valueForProperty(KABNoteProperty)
    }.reject {|k,v| v.nil?}

    {
      'name' => names,
      'business' => business,
      'other' => other,
      'xref' => {
        'ab' => person.valueForProperty('com.apple.uuid')
      },

      # these are lists with zero or more members; duplicates allowed; member order is arbitrary (so we pick
      # a standardized order for list comparison purposes)
      # 'phones' => phones,
      # 'addresses' => addresses,
      # 'emails' => emails,
      # 'links' => links
    }.reject {|k,v| v.nil? || v.empty?}
  end

  def phones
    person.phones.get.map {|e| e.properties_.get}.map do |data|
      {
        'label' => data[:label],
        'phone' => data[:value]
      }
    end #.sort_by {|x| [x['label'], x['phone']].join(' ')}
  end

  def addresses
    person.addresses.get.map {|a| a.properties_.get}.map do |data|
      data.select {|k,v| v != :missing_value && ![:class_, :id_, :formatted_address].include?(k)}.stringify_keys
    end
  end

  def emails
    person.emails.get.map {|e| e.properties_.get}.map do |data|
      {
        'label' => data[:label],
        'email' => data[:value]
      }
    end #.sort_by {|x| [x['label'], x['email']].join(' ')}
  end

  def links
    (urls + social_profiles + im_handles) #.sort_by {|x| [x['label'], x['service'], x['handle'], x['url']].join(' ')}
  end

  def urls
    person.urls.get.map{|u| u.properties_.get}.map do |url|
      {
        'label' => url[:label],
        'url' => url[:value]
      }
    end
  end

  def social_profiles
    person.social_profiles.get.map{|u| u.properties_.get}.map do |profile|
      {
        'service' => profile[:service_name],
        'handle' => profile[:user_name],
        'url' => profile[:url]
      }.reject {|k,v| v.blank? || v == :missing_value}
    end
  end

  def im_handles
    handles1 = %w{AIM ICQ Jabber MSN Yahoo}.map do |service|
      person.send("#{service}_handles").properties_.get.map do |data|
        {
          'service' => service,
          'label' => data[:label],
          'handle' => data[:value]
        }.reject {|k,v| v.blank? || v == :missing_value}
      end
    end.flatten

    ims = person.instant_messages
    handles2 = ims.count.times.map do |i|
      {
        'label' => ims.label.get[i].gsub(/[^A-Za-z]/, '').downcase,
        'service' => ims.service_name.get[i],
        'handle' => ims.user_name.get[i]
      }.reject {|k,v| v.blank? || v == :missing_value}
    end

    (handles1 + handles2).uniq
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

  def to_phone(hash)
    {
      :label => hash['label'],
      :value => hash['phone']
    }
  end

  def to_email(hash)
    {
      :label => hash['label'],
      :value => hash['email']
    }
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
end
