class Macabee::Util
  # compare two arrays of hashes
  # return an actionable object that describes how to convert aoh1 into aoh2
  # array of arrays, the sub-arrays are pairs [A,B]
  # if A is nil, then add B
  # if B is nil, then delete A
  # if B is [], then A is unchanged
  # if A and B are both non-nil and non-empty, then replace A with B

  def self.hasharraydiff(aoh1, aoh2)
    adds = aoh2 - aoh1
    dels = aoh1 - aoh2

    {
      # return list of deletes as indexes into the list,
      # so we can delete them by index (in descending order so the list doesn't get collapsed and mix up the indexes)
      :deletes => dels.map {|h| aoh1.index(h)}.sort.reverse,
      :adds => adds
    }
  end
end
