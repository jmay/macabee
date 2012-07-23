# Macabee::Contacts is ruby representation of Mac Address Book

require "appscript"

class Macabee::Contacts
  attr_reader :ab, :contacts

  # suck all the contacts from local MacOSX Address Book into a single array
  def initialize
    @ab = Appscript.app("Address Book")
  end

  def fetch(ab_id)
    (rec = @ab.people.ID(ab_id)) && transform(rec)
  end

  def all
    @contacts ||= @ab.people.get.map {|c| transform(c)}
  end

  # transform an individual contact to our standard structure
  def transform(p)
    raw = {
      :properties => p.properties_.get.select {|k,v| v != :missing_value && ![:class_, :vcard, :selected, :image].include?(k)},
      :addresses => p.addresses.get.map {|a| a.properties_.get.select {|k,v| v != :missing_value && ![:class_, :id_, :formatted_address].include?(k)}},
      :emails => p.emails.get.map {|a| a.properties_.get.select {|k,v| v != :missing_value && ![:class_, :id_].include?(k)}},
      :phones => p.phones.get.map {|a| a.properties_.get.select {|k,v| v != :missing_value && ![:class_, :id_].include?(k)}},
      :urls => p.urls.get.map {|a| a.properties_.get.select {|k,v| v != :missing_value && ![:class_, :id_].include?(k)}},
      :social_profiles => p.social_profiles.get.map {|a| a.properties_.get.select {|k,v| v != :missing_value && ![:class_, :id_].include?(k)}}
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
      'addresses' => c['addresses'].unroll('label'),
      'emails' => emails,
      'links' => c['urls'].unroll('label').merge(c['social_profiles'].unroll('service_name'))
    }.reject {|k,v| v.nil? || v.empty?}
  end
end
