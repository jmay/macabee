# Macabee::Group is ruby representation of a single MacOSX Address Book group

class Macabee::Group
  attr_reader :ab_group

  def initialize(arg, opts = {})
    if arg.is_a?(ABGroup)
      @ab_group = arg
    else
      # create a new empty group in Address Book with this name
      @ab_group = ABGroup.alloc.init
      set(KABGroupNameProperty, arg[:name])
    end
    @macabee = opts[:macabee]
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
    # ignore any xref values in the comparison data except for any AB value
    abxref = target_hash['xref'] && target_hash['xref'][@macabee.xrefkey]
    target_hash['xref'] = {
      @macabee.xrefkey => abxref
    }

    Macabee::Group.compare(to_hash, target_hash)
  end

  def reverse_compare(target_hash)
    # ignore any xref values in the comparison data except for any AB value
    target_hash['xref'] = {
      @macabee.xrefkey => target_hash['xref'][@macabee.xrefkey]
    }

    Macabee::Group.compare(target_hash, to_hash)
  end

  def patch(diffs)
  end

  # transform an individual group to our standard structure
  def transform
    {
      'name' => ab_group.name,
      'contacts' => contacts,
      'xref' => xref
    }
  end

  def uuid
    to_hash['xref'][@macabee.xrefkey]
  end

  def lookup_uuid
    get(KABUIDProperty)
  end

  def xref
    {
      @macabee.xrefkey => lookup_uuid
    }
  end

  def name
    ab_group.name
  end

  def members
    ab_group.members.map do |p|
      Macabee::Contact.new(p)
    end
  end

  # List of uuid values for all members of the group
  # The OSX `.members` function does not return the list in a consistent order, so sort by UUID value for convenience.
  def contacts
    ab_group.members.map do |p|
      p.valueForProperty(KABUIDProperty)
    end.sort
  end

  def get(property)
    ab_group.valueForProperty(property)
  end

  def set(property, value)
    ab_group.setValue(value, forProperty: property)
  end

  def <<(contact)
    ab_group.addMember(contact.person)
  end
end
