# Macabee::Group is ruby representation of a single MacOSX Address Book group

class Macabee::Group
  attr_reader :ab_group

  def initialize(group)
    @ab_group = group
  end

  def transformed
    @transformed ||= transform
  end

  def to_hash
    transformed
  end

  def compare(target_hash)
  end

  def patch(diffs)
  end

  # transform an individual group to our standard structure
  def transform
    {
      'name' => ab_group.name,
      'contacts' => contacts,
      'xref' => {
        'ab' => ab_group.valueForProperty('com.apple.uuid')
      },
    }
  end

  # List of uuid values for all members of the group
  # The OSX `.members` function does not return the list in a consistent order, so sort by UUID value for convenience.
  def contacts
    ab_group.members.map do |p|
      p.valueForProperty('com.apple.uuid')
    end.sort
  end
end
