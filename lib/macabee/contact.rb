# Macabee::Contact is ruby representation of a single MacOSX Address Book entry

require "active_support/core_ext"

class Macabee::Contact
  attr_reader :person

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

  def unroll(ary, field)
    ary.each_with_object({}) do |hash, memo|
      memo[hash[field]] = hash.reject {|k,v| k == field}
    end
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
      'full' => props['name'],
      'first' => props['first_name'],
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
end
