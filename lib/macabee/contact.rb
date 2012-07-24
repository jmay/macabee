# Macabee::Contact is ruby representation of a single MacOSX Address Book entry

require "active_support/core_ext"
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
    HashDiff.diff(transformed, target_hash)
  end

  def patch(diff)
    diff.each do |action,field,v1,v2|
      abfield = @@mappings[field] || "#{field}-UNMAPPED"

      case action
      when '~' # replace
        puts "person.#{abfield}.set('#{v2}')"
        person.send(abfield).set(v2)

      when '+' # add
        case v1
        when Hash
          value = case abfield
          when :phone
            {
              :label => v1.keys.first,
              :value => v1.values.first['phone']
            }
          when :email
            {
              :label => v1.keys.first,
              :value => v1.values.first['email']
            }
          else
            raise "unknown field '#{abfield}' updated"
          end

          puts "ab.make(:new => #{abfield}, :at => #{self}, :with_properties => #{value.inspect}"
          person.make(:new => abfield, :at => person, :with_properties => value)

        else # should be String
          puts "person.#{abfield}.set('#{v1}')"
          person.send(abfield).set(v1)
        end

      when '-' # delete
        case abfield
        when :phone, :email
          puts "person.send(#{field}).get.select {|x| x.label.get == #{v1.keys.first}}.first.delete"
          rec = person.send(field).get.select {|x| x.label.get == v1.keys.first}.first
          rec.delete
        else
          puts "person.#{abfield}.delete"
          person.send(abfield).delete
        end

      else
        raise "unknown action '#{action}'"
      end
    end
    puts "person.save"
    # person.save
  end

  # transform an individual contact to our standard structure
  def transform
    base_properties = person.properties_.get.select {|k,v| v != :missing_value && ![:class_, :vcard, :selected, :image].include?(k)}
    raw = {
      :addresses => person.addresses.get.map {|a| a.properties_.get.select {|k,v| v != :missing_value && ![:class_, :id_, :formatted_address].include?(k)}},
      :emails => person.emails.get.map {|a| a.properties_.get.select {|k,v| v != :missing_value && ![:class_, :id_].include?(k)}},
      :phones => person.phones.get.map {|a| a.properties_.get.select {|k,v| v != :missing_value && ![:class_, :id_].include?(k)}},
      :urls => person.urls.get.map {|a| a.properties_.get.select {|k,v| v != :missing_value && ![:class_, :id_].include?(k)}},
      :social_profiles => person.social_profiles.get.map {|a| a.properties_.get.select {|k,v| v != :missing_value && ![:class_, :id_].include?(k)}}
    }
    tweaked = {}
    raw.each do |k,v|
      case v
      when Array
        tweaked[k.to_s] = v.map {|h| h.stringify_keys}
      else
        tweaked[k.to_s] = v.stringify_keys
      end
    end
    c = tweaked

    # abxref = base_properties.select {|k,v| k == id_'}
    # don't trust creation_date or modification_date; these are local to the machine

    names = {
      # 'full' => props['name'], # full name field is generated on MacOSX from first+middle+last+suffix
      'first' => base_properties[:first_name],
      'middle' => base_properties[:middle_name],
      'last' => base_properties[:last_name],
      'suffix' => base_properties[:suffix]
    }.reject {|k,v| v.nil?}

    business = base_properties.select {|k,v| [:company, :job_title, :organization].include?(k)}.select {|k,v| v}.stringify_keys
    other = base_properties.select {|k,v| [:note, :birth_date].include?(k)}.select {|k,v| v}.stringify_keys

    # phones = c['phones'].each_with_object({}) {|h,x| x[h['label']] = { 'phone' => h['value'] }}
    # emails = c['emails'].each_with_object({}) {|h,x| x[h['label']] = { 'email' => h['value'] }}

    {
      'name' => names,
      'business' => business,
      'other' => other,
      'xref' => {
        'ab' => base_properties[:id_]
      },
      'phones' => phones,
      'addresses' => unroll(c['addresses'], 'label'),
      'emails' => emails,
      'links' => urls + social_profiles + im_handles
    }.reject {|k,v| v.nil? || v.empty?}
  end

  def phones
    person.phones.get.map {|e| e.properties_.get}.map do |data|
      {
        'label' => data[:label],
        'phone' => data[:value]
      }
    end
  end

  def emails
    person.emails.get.map {|e| e.properties_.get}.map do |data|
      {
        'label' => data[:label],
        'email' => data[:value]
      }
    end
  end

  def urls
    person.urls.get.map{|u| u.properties_.get}.map do |url|
      {
        'label' => url[:label],
        'url' => url[:value]
      }
      # a.properties_.get.select {|k,v| v != :missing_value && ![:class_, :id_].include?(k)}},
    end
  end

  def social_profiles
    person.social_profiles.get.map{|u| u.properties_.get}.map do |profile|
      {
        'service' => profile[:service_name],
        'handle' => profile[:user_name],
        'url' => profile[:url]
      }.reject {|k,v| v.nil? || v.empty?}
    end
    # .get.map {|a| a.properties_.get.select {|k,v| v != :missing_value && ![:class_, :id_].include?(k)}}
  end

  def im_handles
    %w{AIM ICQ Jabber MSN Yahoo}.map do |service|
      person.send("#{service}_handles").properties_.get.map do |data|
        {
          'service' => service,
          'label' => data[:label],
          'handle' => data[:value]
        }.reject {|k,v| v.nil? || v.empty?}
      end
    end.flatten
  end

  private

  def unroll(ary, field)
    ary.each_with_object({}) do |hash, memo|
      memo[hash[field]] = hash.reject {|k,v| k == field}
    end
  end

  def reroll(hash, fieldname)
    k,v = hash.first
    v.merge(fieldname => k)
  end
end
