class PropertyList < Array

  def initialize(propertySet)
    @propertySet = propertySet
    super(propertySet.to_ary)
    resetSorting
    addSortingCriteria('seqno', true, -1)
  end

  def setSorting(modes)
    resetSorting
    modes.each do |mode|
      addSortingCriteria(*mode)
    end
    self.sort!
  end

  def resetSorting
    @sortingLevels = 0
    @sortingCriteria = []
    @sortingUp = []
    @scenarioIdx = []
  end

  def addSortingCriteria(criteria, up, scIdx)
    @sortingCriteria.push(criteria)
    @sortingUp.push(up)
    @scenarioIdx.push(scIdx)
    @sortingLevels += 1
  end

  def sort!
    super do |a, b|
      res = 0
      0.upto(@sortingLevels) do |i|
        if @scenarioIdx[i] < 0
          res = a.get(@sortingCriteria[i]) <=> b.get(@sortingCriteria[i])
        else
          res = a[@sortingCriteria[i], @scenarioIdx[i]] <=>
                b[@sortingCriteria[i], @scenarioIdx[i]]
        end
        break if res != 0
      end
      res
    end
  end

  def to_s
    res = ""
    each { |i| res += "#{i.get('id')}: #{i.get('name')}\n" }
    res
  end

end

