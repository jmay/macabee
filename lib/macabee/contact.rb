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

    'other.job_title' => :job_title,

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
    person.save
  end

  # transform an individual contact to our standard structure
  def transform
    raw = {
      :properties => person.properties_.get.select {|k,v| v != :missing_value && ![:class_, :vcard, :selected, :image].include?(k)},
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

    props = c['properties']

    abxref = props.select {|k,v| k == 'id_'}
    # don't trust creation_date or modification_date; these are local to the machine

    names = {
      # 'full' => props['name'], # full name field is generated on MacOSX from first+middle+last+suffix
      'first' => props['first_name'],
      'middle' => props['middle_name'],
      'last' => props['last_name'],
      'suffix' => props['suffix']
    }.reject {|k,v| v.nil?}

    other = props.select {|k,v| ['company', 'note', 'birth_date', 'job_title', 'organization'].include?(k)}.select {|k,v| v}
    phones = c['phones'].each_with_object({}) {|h,x| x[h['label']] = { 'phone' => h['value'] }}
    emails = c['emails'].each_with_object({}) {|h,x| x[h['label']] = { 'email' => h['value'] }}

    phone_mappings = {'value' => 'phone'}
      
    {
      'name' => names,
      'other' => other,
      'xref' => {
        'ab' => abxref
      },
      'phones' => phones,
      'addresses' => unroll(c['addresses'], 'label'),
      'emails' => emails,
      'links' => unroll(c['urls'], 'label').merge(unroll(c['social_profiles'], 'service_name'))
    }.reject {|k,v| v.nil? || v.empty?}
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
