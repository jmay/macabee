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
      'name' => @ab_group.name.get,
      'contacts' => contacts
    }
  end

  def contacts
    @ab_group.people.get.map do |p|
      p.id_.get
    end
  end
end
