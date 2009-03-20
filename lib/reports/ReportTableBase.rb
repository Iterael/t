#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = ReportTableBase.rb -- The TaskJuggler III Project Management Software
#
# Copyright (c) 2006, 2007, 2008, 2009 by Chris Schlaeger <cs@kde.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#

require 'reports/GanttChart'
require 'reports/ReportTableLegend'
require 'reports/ColumnTable'
require 'Query'

class TaskJuggler

  # This is base class for all types of tabular report elements. All tabular
  # report elements are converted to an abstract (output independent)
  # intermediate form first, before the are turned into the requested output
  # format.
  class ReportTableBase

    attr_reader :legend

    # Generate a new ReportTableBase object.
    def initialize(report)
      @report = report
      @report.table = self
      @project = report.project

      # Reference to the intermediate representation.
      @table = nil
      @start = a('start')
      @end = a('end')

      @legend = ReportTableLegend.new
      @userDefinedPeriod = !(@report.inherited('end') &&
                             @report.inherited('start'))

      @propertiesById = {
        # ID               Header        Indent  Align   Calced. Scen Spec.
        'complete'    => [ 'Completion', false,  :right, true,   true ],
        'cost'        => [ 'Cost',       true,   :right, true,   true ],
        'duration'    => [ 'Duration',   true,   :right, true,   true ],
        'effort'      => [ 'Effort',     true,   :right, true,   true ],
        'id'          => [ 'Id',         false,  :left,  true,   false ],
        'line'        => [ 'Line No.',   false,  :right, true,   false ],
        'name'        => [ 'Name',       true,   :left,  false,  false ],
        'no'          => [ 'No.',        false,  :right, true,   false ],
        'rate'        => [ 'Rate',       true,   :right, true,   true ],
        'revenue'     => [ 'Revenue',    true,   :right, true,   true ],
        'wbs'         => [ 'WBS',        false,  :left,  true,   false ]
      }
      @propertiesByType = {
        # Type                  Indent  Align
        DateAttribute      => [ false,  :left ],
        FixnumAttribute    => [ false,  :right ],
        FloatAttribute     => [ false,  :right ],
        RichTextAttribute  => [ false,  :left ],
        StringAttribute    => [ false,  :left ]
      }
    end

    # Convenience function to access a report attribute
    def a(attribute)
      @report.get(attribute)
    end

    # This is an abstract member that all sub classes must re-implement. It may
    # or may not do something though.
    def generateIntermediateFormat
      raise 'This function must be overriden by derived classes.'
    end

    # Turn the ReportTableBase into an equivalent HTML element tree.
    def to_html
      html = []

      if a('prolog')
        a('prolog').sectionNumbers = false
        html << a('prolog').to_html
      end

      html << (table = XMLElement.new('table', 'summary' => 'Report Table',
                                     'cellspacing' => '2', 'border' => '0',
                                     'cellpadding' => '0', 'align' => 'center',
                                     'class' => 'tabback'))

      # The headline is put in a sub-table to appear bigger.
      if a('headline')
        table << (thead = XMLElement.new('thead'))
        thead << (tr = XMLElement.new('tr'))
        tr << (td = XMLElement.new('td'))
        td << (table1 = XMLElement.new('table', 'summary' => 'headline',
                                       'cellspacing' => '1', 'border' => '0',
                                       'cellpadding' => '5',
                                       'align' => 'center', 'width' => '100%'))
        table1 << (tr1 = XMLElement.new('tr'))
        tr1 << (td1 = XMLElement.new('td', 'align' => 'center',
                                     'style' => 'font-size:16px; ' +
                                                'font-weight:bold',
                                     'class' => 'tabfront'))
        td1 << XMLNamedText.new(a('headline'), 'p')
      end

      # Now generate the actual table with the data.
      table << (tbody = XMLElement.new('tbody'))
      tbody << (tr = XMLElement.new('tr'))
      tr << (td = XMLElement.new('td'))
      td << @table.to_html

      # Embedd the caption as RichText into the table footer.
      if a('caption')
        tbody << (tr = XMLElement.new('tr'))
        tr << (td = XMLElement.new('td', 'class' => 'tabback'))
        td << (div = XMLElement.new('div', 'class' => 'caption',
                                    'style' => 'margin:1px'))
        a('caption').sectionNumbers = false
        div << a('caption').to_html
      end

      # A sub-table with the legend.
      tbody << (tr = XMLElement.new('tr', 'style' => 'font-size:10px;'))
      tr << (td = XMLElement.new('td', 'style' =>
                                 'padding-left:1px; padding-right:1px;'))
      td << @legend.to_html

      # The footer with some administrative information.
      tbody << (tr = XMLElement.new('tr', 'style' => 'font-size:9px'))
      tr << (td = XMLElement.new('td', 'class' => 'tabfooter'))
      td << XMLText.new(@project['copyright'] + " - ") if @project['copyright']
      td << XMLText.new("Project: #{@project['name']} " +
                        "Version: #{@project['version']} - " +
                        "Created on #{TjTime.now.to_s("%Y-%m-%d %H:%M:%S")} " +
                        "with ")
      td << XMLNamedText.new("#{AppConfig.packageName}", 'a',
                             'href' => "#{AppConfig.contact}")
      td << XMLText.new(" v#{AppConfig.version}")

      if a('epilog')
        a('epilog').sectionNumbers = false
        html << a('epilog').to_html
      end

      html
    end

    # Convert the table into an Array of Arrays. It has one Array for each
    # line. The nested Arrays have one String for each column.
    def to_csv
      @table.to_csv
    end

    # Take the complete task list and remove all tasks that are matching the
    # hide expression, the rollup Expression or are not a descendent of
    # taskRoot. In case resource is not nil, a task is only included if
    # the resource is allocated to it in any of the reported scenarios.
    def filterTaskList(list_, resource, hideExpr, rollupExpr)
      list = PropertyList.new(list_)
      if (taskRoot = a('taskRoot'))
        # Remove all tasks that are not descendents of the taskRoot.
        list.delete_if { |task| !task.isChildOf?(taskRoot) }
      end

      if resource
        # If we have a resource we need to check that the resource is allocated
        # to the tasks in any of the reported scenarios.
        list.delete_if do |task|
          delete = true
          a('scenarios').each do |scenarioIdx|
            if task['assignedresources', scenarioIdx].include?(resource)
              delete = false
              break;
            end
          end
          delete
        end
      end

      # Remove all tasks that don't overlap with the reported interval.
      list.delete_if do |task|
        delete = true
        a('scenarios').each do |scenarioIdx|
          iv = Interval.new(task['start', scenarioIdx].nil? ?
                            @project['start'] : task['start', scenarioIdx],
                            task['end', scenarioIdx].nil? ?
                            @project['end'] : task['end', scenarioIdx])
          # Special case to include milestones at the report end.
          if iv.start == iv.end && iv.end == @end
            iv.start = iv.end = iv.start - 1
          end
          if iv.overlaps?(Interval.new(@start, @end))
            delete = false
            break;
          end
        end
        delete
      end

      standardFilterOps(list, hideExpr, rollupExpr, resource, taskRoot)
    end

    # Take the complete resource list and remove all resources that are matching
    # the hide expression, the rollup Expression or are not a descendent of
    # resourceRoot. In case task is not nil, a resource is only included if
    # it is assigned to the task in any of the reported scenarios.
    def filterResourceList(list_, task, hideExpr, rollupExpr)
      list = PropertyList.new(list_)
      if (resourceRoot = a('resourceRoot'))
        # Remove all resources that are not descendents of the resourceRoot.
        list.delete_if { |resource| !resource.isChildOf?(resourceRoot) }
      end

      if task
        # If we have a task we need to check that the resources are assigned
        # to the task in any of the reported scenarios.
        iv = Interval.new(@start, @end)
        list.delete_if do |resource|
          delete = true
          a('scenarios').each do |scenarioIdx|
            if resource.allocated?(scenarioIdx, iv, task)
              delete = false
              break;
            end
          end
          delete
        end
      end

      standardFilterOps(list, hideExpr, rollupExpr, task, resourceRoot)
    end

    # This is the default attribute value to text converter. It is used
    # whenever we need no special treatment.
    def cellText(property, scenarioIdx, colId)
      if property.is_a?(Resource)
        propertyList = @project.resources
      elsif property.is_a?(Task)
        propertyList = @project.tasks
      else
        raise "Fatal Error: Unknown property #{property.class}"
      end

      begin
        # Get the value no matter if it's scenario specific or not.
        if propertyList.scenarioSpecific?(colId)
          value = property.getAttr(colId, scenarioIdx)
        else
          value = property.getAttr(colId)
        end

        type = propertyList.attributeType(colId)
        if value.nil?
          if type == DateAttribute
            nil
          else
            ''
          end
        else
          # Certain attribute types need special treatment.
          if type == DateAttribute
            value.value.to_s(a('timeFormat'))
          elsif type == RichTextAttribute
            value.value
          else
            value.to_s
          end
        end
      rescue TjException
        ''
      end
    end

    # This function returns true if the values for the _colId_ column need to be
    # calculated.
    def calculated?(colId)
      if @propertiesById.has_key?(colId)
        return @propertiesById[colId][3]
      end
      return false
    end

    # This functions returns true if the values for the _col_id_ column are
    # scenario specific.
    def scenarioSpecific?(colId)
      if @propertiesById.has_key?(colId)
        return @propertiesById[colId][4]
      end
      return false
    end

    # Return if the column values should be indented based on the _colId_ or the
    # _propertyType_.
    def indent(colId, propertyType)
      if @propertiesById.has_key?(colId)
        return @propertiesById[colId][1]
      elsif @propertiesByType.has_key?(propertyType)
        return @propertiesByType[propertyType][0]
      else
        false
      end
    end

    # Return the alignment of the column based on the _colId_ or the
    # _propertyType_.
    def alignment(colId, propertyType)
      if @propertiesById.has_key?(colId)
        return @propertiesById[colId][2]
      elsif @propertiesByType.has_key?(propertyType)
        return @propertiesByType[propertyType][1]
      else
        :center
      end
    end

    # Returns the default column title for the columns _id_.
    def defaultColumnTitle(id)
      # Return an empty string for some special columns that don't have a fixed
      # title.
      specials = %w( chart hourly daily weekly monthly quarterly yearly)
      return '' if specials.include?(id)

      # Return the title for build-in hardwired columns.
      return @propertiesById[id][0] if @propertiesById.include?(id)

      # Otherwise we have to see if the column id is a task or resource
      # attribute and return it's value.
      (name = @project.tasks.attributeName(id)).nil? &&
      (name = @project.resources.attributeName(id)).nil?
      name
    end

    def supportedColumns
      @propertiesById.keys
    end

  protected
    # In case the user has not specified the report period, we try to fit all
    # the _tasks_ in and add an extra 5% time at both ends. _scenarios_ is a
    # list of scenario indexes.
    def adjustReportPeriod(tasks, scenarios)
      return if tasks.empty?

      @start = @end = nil
      scenarios.each do |scenarioIdx|
        tasks.each do |task|
          date = task['start', scenarioIdx] || @project['start']
          @start = date if @start.nil? || date < @start
          date = task['end', scenarioIdx] || @project['end']
          @end = date if @end.nil? || date > @end
        end
      end
      # Make sure we have a minimum width of 1 day
      @end = @start + 60 * 60 * 24 if @end < @start + 60 * 60 * 24
      padding = ((@end - @start) * 0.10).to_i
      @start -= padding
      @end += padding
    end

    # Generates cells for the table header. _columnDef_ is the
    # TableColumnDefinition object that describes the column. Based on the id of
    # the column different actions need to be taken to generate the header text.
    def generateHeaderCell(columnDef)
      case columnDef.id
      when 'chart'
        # For the 'chart' column we generate a GanttChart object. The sizes are
        # set so that the lines of the Gantt chart line up with the lines of the
        # table.
        gantt = GanttChart.new(a('now'),
                               a('weekStartsMonday'), self)
        gantt.generateByScale(@start, @end, columnDef.scale)
        # The header consists of 2 lines separated by a 1 pixel boundary.
        gantt.header.height = @table.headerLineHeight * 2 + 1
        # The maximum width of the chart. In case it needs more space, a
        # scrollbar is shown or the chart gets truncated depending on the output
        # format.
        gantt.viewWidth = columnDef.width
        column = ReportTableColumn.new(@table, columnDef, '')
        column.cell1.special = gantt
        column.cell2.hidden = true
        column.scrollbar = gantt.hasScrollbar?
        @table.equiLines = true
      when 'hourly'
        genCalChartHeader(columnDef, @start.midnight, :sameTimeNextHour,
                          :weekdayAndDate, :hour)
      when 'daily'
        genCalChartHeader(columnDef, @start.midnight, :sameTimeNextDay,
                          :shortMonthName, :day)
      when 'weekly'
        genCalChartHeader(columnDef,
                          @start.beginOfWeek(a('weekStartsMonday')),
                          :sameTimeNextWeek, :shortMonthName, :day)
      when 'monthly'
        genCalChartHeader(columnDef, @start.beginOfMonth, :sameTimeNextMonth,
                          :year, :shortMonthName)
      when 'quarterly'
        genCalChartHeader(columnDef, @start.beginOfQuarter,
                          :sameTimeNextQuarter, :year, :quarterName)
      when 'yearly'
        genCalChartHeader(columnDef, @start.beginOfYear, :sameTimeNextYear,
                          nil, :year)
      else
        # This is the most common case. It does not need any special treatment.
        # We just set the pre-defined or user-defined column title in the first
        # row of the header. The 2nd row is not visible.
        column = ReportTableColumn.new(@table, columnDef, columnDef.title)
        column.cell1.rows = 2
        column.cell2.hidden = true
      end
    end

    # Generate a ReportTableLine for each of the tasks in _taskList_. In case
    # _resourceList_ is not nil, it also generates the nested resource lines for
    # each resource that is assigned to the particular task. If _scopeLine_
    # is defined, the generated task lines will be within the scope this resource
    # line.
    def generateTaskList(taskList, resourceList, scopeLine)
      queryAttrs = { 'scopeProperty' => scopeLine ? scopeLine.property : nil,
                     'loadUnit' => a('loadUnit'),
                     'numberFormat' => a('numberFormat'),
                     'currencyFormat' => a('currencyFormat'),
                     'start' => @start, 'end' => @end,
                     'costAccount' => a('costAccount'),
                     'revenueAccount' => a('revenueAccount') }
      taskList.query = Query.new(queryAttrs)
      taskList.sort!

      # The primary line counter. Is not used for enclosed lines.
      no = 0
      # The scope line counter. It's reset for each new scope.
      lineNo = scopeLine ? scopeLine.lineNo : 0
      # Init the variable to get a larger scope
      line = nil
      taskList.each do |task|
        no += 1
        Log.activity if lineNo % 10 == 0
        lineNo += 1
        a('scenarios').each do |scenarioIdx|
          # Generate line for each task.
          line = ReportTableLine.new(@table, task, scopeLine)

          line.no = no unless scopeLine
          line.lineNo = lineNo
          line.subLineNo = @table.lines
          setIndent(line, a('taskRoot'), taskList.treeMode?)

          # Generate a cell for each column in this line.
          a('columns').each do |columnDef|
            next unless generateTableCell(line, task, columnDef, scenarioIdx)
          end
        end

        if resourceList
          # If we have a resourceList we generate nested lines for each of the
          # resources that are assigned to this task and pass the user-defined
          # filter.
          resourceList.setSorting(a('sortResources'))
          assignedResourceList = filterResourceList(resourceList, task,
              a('hideResource'), a('rollupResource'))
          assignedResourceList.sort!
          lineNo = generateResourceList(assignedResourceList, nil, line)
        end
      end
      lineNo
    end

    # Generate a ReportTableLine for each of the resources in _resourceList_. In
    # case _taskList_ is not nil, it also generates the nested task lines for
    # each task that the resource is assigned to. If _scopeLine_ is defined, the
    # generated resource lines will be within the scope this task line.
    def generateResourceList(resourceList, taskList, scopeLine)
      queryAttrs = { 'scopeProperty' => scopeLine ? scopeLine.property : nil,
                     'loadUnit' => a('loadUnit'),
                     'numberFormat' => a('numberFormat'),
                     'currencyFormat' => a('currencyFormat'),
                     'start' => @start, 'end' => @end,
                     'costAccount' => a('costAccount'),
                     'revenueAccount' => a('revenueAccount') }
      resourceList.query = Query.new(queryAttrs)
      resourceList.sort!

      # The primary line counter. Is not used for enclosed lines.
      no = 0
      # The scope line counter. It's reset for each new scope.
      lineNo = scopeLine ? scopeLine.lineNo : 0
      # Init the variable to get a larger scope
      line = nil
      resourceList.each do |resource|
        no += 1
        Log.activity if lineNo % 10 == 0
        lineNo += 1
        a('scenarios').each do |scenarioIdx|
          # Generate line for each resource.
          line = ReportTableLine.new(@table, resource, scopeLine)

          line.no = no unless scopeLine
          line.lineNo = lineNo
          line.subLineNo = @table.lines
          setIndent(line, a('resourceRoot'), resourceList.treeMode?)

          # Generate a cell for each column in this line.
          a('columns').each do |column|
            next unless generateTableCell(line, resource, column, scenarioIdx)
          end
        end

        if taskList
          # If we have a taskList we generate nested lines for each of the
          # tasks that the resource is assigned to and pass the user-defined
          # filter.
          taskList.setSorting(a('sortTasks'))
          assignedTaskList = filterTaskList(taskList, resource,
                                            a('hideTask'),
                                            a('rollupTask'))
          assignedTaskList.sort!
          lineNo = generateTaskList(assignedTaskList, nil, line)
        end
      end
      lineNo
    end

  private

    # This function implements the generic filtering functionality for all kinds
    # of lists.
    def standardFilterOps(list, hideExpr, rollupExpr, scopeProperty, root)
      # Remove all properties that the user wants to have hidden.
      if hideExpr
        list.delete_if do |property|
          hideExpr.eval(property, scopeProperty)
        end
      end

      # Remove all children of properties that the user has rolled-up.
      if rollupExpr
        list.delete_if do |property|
          parent = property.parent
          delete = false
          while (parent)
            if rollupExpr.eval(parent, scopeProperty)
              delete = true
              break
            end
            parent = parent.parent
          end
          delete
        end
      end

      # Re-add parents in tree mode
      if list.treeMode?
        parents = []
        list.each do |property|
          parent = property
          while (parent = parent.parent)
            parents << parent unless list.include?(parent) ||
                                     parents.include?(parent)
            break if parent == root
          end
        end
        list.append(parents)
      end

      list
    end

    # This function converts number to strings that may include a unit. The
    # unit is determined by @loadUnit. In the automatic modes, the shortest
    # possible result is shown and the unit is always appended. _value_ is the
    # value to convert. _factors_ determines the conversion factors for the
    # different units.
    # TODO: Delete when all users have been migrated to use Query!
    def scaleValue(value, factors)
      loadUnit = a('loadUnit')
      numberFormat = a('numberFormat')

      if loadUnit == :shortauto || loadUnit == :longauto
        # We try all possible units and store the resulting strings here.
        options = []
        # For each of the units we can define a maximum value that the value
        # should not exceed. A maximum of 0 means no limit.
        max = [ 60, 48, 0, 8, 24, 0 ]

        i = 0
        shortest = nil
        factors.each do |factor|
          scaledValue = value * factor
          str = numberFormat.format(scaledValue)
          # We ignore results that are 0 or exceed the maximum. To ensure that
          # we have at least one result the unscaled value is always taken.
          if (factor != 1.0 && scaledValue == 0) ||
             (max[i] != 0 && scaledValue > max[i])
            options << nil
          else
            options << str
          end
          i += 1
        end

        # Default to days in case they are all the same.
        shortest = 2
        # Find the shortest option.
        6.times do |j|
          shortest = j if options[j] &&
                          options[j].length < options[shortest].length
        end

        str = options[shortest]
        if loadUnit == :longauto
          # For the long units we handle singular and plural properly. For
          # English we just need to append an 's', but this code will work for
          # other languages as well.
          units = []
          if str == "1"
            units = %w( minute hour day week month year )
          else
            units = %w( minutes hours days weeks months years )
          end
          str += ' ' + units[shortest]
        else
          str += %w( min h d w m y )[shortest]
        end
      else
        # For fixed units we just need to do the conversion. No unit is
        # included.
        units = [ :minutes, :hours, :days, :weeks, :months, :years ]
        str = numberFormat.format(value * factors[units.index(loadUnit)])
      end
      str
    end

    # Generate the header data for calendar tables. They consists of columns for
    # each hour, day, week, etc. _columnDef_ is the definition of the columns.
    # _t_ is the start time for the calendar. _sameTimeNextFunc_ is a function
    # that is called to advance _t_ to the next table column interval.
    # _name1Func_ and _name2Func_ are functions that return the upper and lower
    # title of the particular column.
    def genCalChartHeader(columnDef, t, sameTimeNextFunc, name1Func, name2Func)
      tableColumn = ReportTableColumn.new(@table, columnDef, '')

      # Calendar chars only work when all lines have same height.
      @table.equiLines = true

      # Embedded tables have unpredictable width. So we always need to make room
      # for a potential scrollbar.
      tableColumn.scrollbar = true

      # Create the table that is embedded in this column.
      tableColumn.cell1.special = table = ColumnTable.new
      table.equiLines = true
      tableColumn.cell2.hidden = true
      table.maxWidth = columnDef.width

      # Iterate over the report interval until we hit the end date. The
      # iteration is done with 2 nested loops. The outer loops generates the
      # intervals for the upper (larger) scale. The inner loop generates the
      # lower (smaller) scale.
      while t < @end
        cellsInInterval = 0
        # Label for upper scale. The yearly calendar only has a lower scale.
        currentInterval = t.send(name1Func) if name1Func
        firstColumn = nil
        # The innter loops terminates when the label for the upper scale has
        # changed to the next scale cell.
        while t < @end && (name1Func.nil? ||
                           t.send(name1Func) == currentInterval)
          # call TjTime::sameTimeNext... function to get the end of the column.
          nextT = t.send(sameTimeNextFunc)
          iv = Interval.new(t, nextT)
          # Create the new column object.
          column = ReportTableColumn.new(table, nil, '')
          # Store the date of the column in the original form.
          column.cell1.data = t.to_s(a('timeFormat'))
          # The upper scale cells will be merged into one large cell that spans
          # all lower scale cells that belong to this upper cell.
          if firstColumn.nil?
            firstColumn = column
            column.cell1.text = currentInterval.to_s
          else
            column.cell1.hidden = true
          end
          column.cell2.text = t.send(name2Func).to_s
          # TODO: The width should be taken from some data structure.
          column.cell2.width = 20
          # Off-duty cells will have a different color than working time cells.
          unless @project.isWorkingTime(iv)
            column.cell2.category = 'tabhead_offduty'
          end
          cellsInInterval += 1

          t = nextT
        end
        # The the first upper scale cell how many trailing hidden cells are
        # following.
        firstColumn.cell1.columns = cellsInInterval
      end
    end

    # Generate a cell of the table. _line_ is the ReportTableLine that this cell
    # should belong to. _property_ is the PropertyTreeNode that is reported in
    # this _line_. _columnDef_ is the TableColumnDefinition of the column this
    # cell should belong to. _scenarioIdx_ is the index of the scenario that is
    # reported in this _line_.
    #
    # There are 4 kinds of cells. The most simple one is the standard cell. It
    # literally reports the value of a property attribute. Calculated cells are
    # more flexible. They contain computed values. The values are computed at
    # cell generation time. The calendar columns consist of multiple sub
    # columns. In such a case many cells are generated with a single call of
    # this method. The last kind of cell is actually not a cell. It just
    # generates the chart objects that belong to the property in this line.
    def generateTableCell(line, property, columnDef, scenarioIdx)
      case columnDef.id
      when 'chart'
        # Generate a hidden cell. The real meat is in the actual chart object,
        # not in this cell.
        cell = ReportTableCell.new(line)
        cell.hidden = true
        cell.text = nil
        # The GanttChart can be reached via the special variable of the column
        # header.
        chart = columnDef.column.cell1.special
        GanttLine.new(chart, property,
                      line.scopeLine ? line.scopeLine.property : nil,
                      scenarioIdx, (line.subLineNo - 1) * (line.height + 1),
                      line.height)
        return true
      # The calendar cells can be all generated by the same function. But we
      # need to use different parameters.
      when 'hourly'
        start = @start.midnight
        sameTimeNextFunc = :sameTimeNextHour
      when 'daily'
        start = @start.midnight
        sameTimeNextFunc = :sameTimeNextDay
      when 'weekly'
        start = @start.beginOfWeek(a('weekStartsMonday'))
        sameTimeNextFunc = :sameTimeNextWeek
      when 'monthly'
        start = @start.beginOfMonth
        sameTimeNextFunc = :sameTimeNextMonth
      when 'quarterly'
        start = @start.beginOfQuarter
        sameTimeNextFunc = :sameTimeNextQuarter
      when 'yearly'
        start = @start.beginOfYear
        sameTimeNextFunc = :sameTimeNextYear
      else
        if calculated?(columnDef.id)
          genCalculatedCell(scenarioIdx, line, columnDef, property)
          return true
        else
          return genStandardCell(scenarioIdx, line, columnDef)
        end
      end

      # The calendar cells don't live in this ReportTable but in an embedded
      # ReportTable that can be reached via the column header special variable.
      # For embedded column tables we need to create a new line.
      tcLine = ReportTableLine.new(columnDef.column.cell1.special,
                                   line.property, line.scopeLine)

      # Depending on the property type we use different generator functions.
      if property.is_a?(Task)
        genCalChartTaskCell(scenarioIdx, tcLine, columnDef, start,
                            sameTimeNextFunc)
      elsif property.is_a?(Resource)
        genCalChartResourceCell(scenarioIdx, tcLine, columnDef, start,
                                sameTimeNextFunc)
      else
        raise "Unknown property type #{property.class}"
      end
      true
    end

    # Generate a ReportTableCell filled the value of an attribute of the
    # property that line is for. It returns true if the cell exists, false for a
    # hidden cell.
    def genStandardCell(scenarioIdx, line, columnDef)
      property = line.property
      # Create a new cell
      cell = newCell(line, cellText(property, scenarioIdx, columnDef.id))

      if property.is_a?(Task)
        properties = @project.tasks
      elsif property.is_a?(Resource)
        properties = @project.resources
      else
        raise "Unknown property type #{property.class}"
      end

      # Check if we are dealing with multiple scenarios.
      if a('scenarios').length > 1
        # Check if the attribute is not scenario specific
        unless properties.scenarioSpecific?(columnDef.id)
          if scenarioIdx == a('scenarios').first
            #  Use a somewhat bigger font.
            cell.fontSize = 15
          else
            # And hide the cells for all but the first scenario.
            cell.hidden = true
            return false
          end
          cell.rows = a('scenarios').length
        end
      end

      setStandardCellAttributes(cell, columnDef,
                                properties.attributeType(columnDef.id), line)

      scopeProperty = line.scopeLine ? line.scopeLine.property : nil
      query = Query.new('property' => property,
                        'scopeProperty' => scopeProperty,
                        'attributeId' => columnDef.id,
                        'scenarioIdx' => scenarioIdx,
                        'loadUnit' => a('loadUnit'),
                        'numberFormat' => a('numberFormat'),
                        'currencyFormat' => a('currencyFormat'),
                        'start' => @start, 'end' => @end,
                        'costAccount' => a('costAccount'),
                        'revenueAccount' => a('revenueAccount'))
      if cell.text
        if columnDef.cellText
          cell.text = expandMacros(columnDef.cellText, cell.text, query)
        end
      else
        cell.text = '<Error>'
        cell.fontColor = 0xFF0000
      end

      setCellURL(cell, columnDef, query)
      true
    end

    # Generate a ReportTableCell filled with a calculted value from the property
    # or other sources of information. It returns true if the cell exists, false
    # for a hidden cell. _scenarioIdx_ is the index of the reported scenario.
    # _line_ is the ReportTableLine of the cell. _columnDef_ is the
    # TableColumnDefinition of the column. _property_ is the PropertyTreeNode
    # that is reported in this cell.
    def genCalculatedCell(scenarioIdx, line, columnDef, property)
      # Create a new cell
      cell = newCell(line)

      unless scenarioSpecific?(columnDef.id)
        if scenarioIdx != a('scenarios').first
          cell.hidden = true
          return false
        end
        cell.rows = a('scenarios').length
      end

      setStandardCellAttributes(cell, columnDef, nil, line)

      return if columnDef.hideCellText &&
                endcolumnDef.hideCellText.eval(property, scopeProperty)

      scopeProperty = line.scopeLine ? line.scopeLine.property : nil
      query = Query.new('property' => property,
                        'scopeProperty' => scopeProperty,
                        'attributeId' => columnDef.id,
                        'scenarioIdx' => scenarioIdx,
                        'loadUnit' => a('loadUnit'),
                        'numberFormat' => a('numberFormat'),
                        'currencyFormat' => a('currencyFormat'),
                        'start' => @start, 'end' => @end,
                        'costAccount' => a('costAccount'),
                        'revenueAccount' => a('revenueAccount'))
      query.process
      cell.text = query.result

      # Some columns need some extra care.
      case columnDef.id
      when 'line'
        cell.text = line.lineNo.to_s
      when 'no'
        cell.text = line.no.to_s
      when 'wbs'
        cell.indent = 2 if line.scopeLine
      end

      if columnDef.cellText
        cell.text = expandMacros(columnDef.cellText, cell.text, query)
      end
      setCellURL(cell, columnDef, query)
    end

    # Generate the cells for the task lines of a calendar column. These lines do
    # not directly belong to the @table object but to an embedded ColumnTable
    # object. Therefor a single @table column usually has many cells on each
    # single line. _scenarioIdx_ is the index of the scenario that is reported
    # in this line. _line_ is the @table line. _t_ is the start date for the
    # calendar. _sameTimeNextFunc_ is the function that will move the date to
    # the next cell.
    def genCalChartTaskCell(scenarioIdx, line, columnDef, t, sameTimeNextFunc)
      task = line.property
      # Find out if we have an enclosing resource scope.
      if line.scopeLine && line.scopeLine.property.is_a?(Resource)
        resource = line.scopeLine.property
      else
        resource = nil
      end

      # Get the interval of the task. In case a date is invalid due to a
      # scheduling problem, we use the full project interval.
      taskIv = Interval.new(task['start', scenarioIdx].nil? ?
                            @project['start'] : task['start', scenarioIdx],
                            task['end', scenarioIdx].nil? ?
                            @project['end'] : task['end', scenarioIdx])

      query = Query.new('property' => task, 'scopeProperty' => resource,
                        'scenarioIdx' => scenarioIdx,
                        'loadUnit' => a('loadUnit'),
                        'numberFormat' => a('numberFormat'),
                        'currencyFormat' => a('currencyFormat'),
                        'costAccount' => a('costAccount'),
                        'revenueAccount' => a('revenueAccount'))

      firstCell = nil
      while t < @end
        # Create a new cell
        cell = newCell(line)

        # call TjTime::sameTimeNext... function
        nextT = t.send(sameTimeNextFunc)
        cellIv = Interval.new(t, nextT)
        case columnDef.content
        when 'empty'
          # We only generate cells will different background colors.
        when 'load'
          query.attributeId = 'effort'
          query.startIdx = t
          query.endIdx = nextT
          query.process
          # To increase readability, we don't show 0.0 values.
          cell.text = query.result if query.numericalResult > 0.0
        else
          raise "Unknown column content #{column.content}"
        end

        # Determine cell category (mostly the background color)
        if cellIv.overlaps?(taskIv)
          cell.category = task.container? ? 'calconttask' : 'caltask'
        elsif !@project.isWorkingTime(cellIv)
          cell.category = 'offduty'
        else
          cell.category = 'taskcell'
        end
        cell.category += line.property.get('index') % 2  == 1 ? '1' : '2'

        tryCellMerging(cell, line, firstCell)

        t = nextT
        firstCell = cell unless firstCell
      end

      legend.addCalendarItem('Container Task', 'calconttask1')
      legend.addCalendarItem('Task', 'caltask1')
      legend.addCalendarItem('Off duty time', 'offduty')
    end

    # Generate the cells for the resource lines of a calendar column. These
    # lines do not directly belong to the @table object but to an embedded
    # ColumnTable object. Therefor a single @table column usually has many cells
    # on each single line. _scenarioIdx_ is the index of the scenario that is
    # reported in this line. _line_ is the @table line. _t_ is the start date
    # for the calendar. _sameTimeNextFunc_ is the function that will move the
    # date to the next cell.
    def genCalChartResourceCell(scenarioIdx, line, columnDef, t,
                                sameTimeNextFunc)
      resource = line.property
      # Find out if we have an enclosing task scope.
      if line.scopeLine && line.scopeLine.property.is_a?(Task)
        task = line.scopeLine.property
        # Get the interval of the task. In case a date is invalid due to a
        # scheduling problem, we use the full project interval.
        taskIv = Interval.new(task['start', scenarioIdx].nil? ?
                              @project['start'] : task['start', scenarioIdx],
                              task['end', scenarioIdx].nil? ?
                              @project['end'] : task['end', scenarioIdx])
      else
        task = nil
      end

      query = Query.new('property' => resource,
                        'scenarioIdx' => scenarioIdx,
                        'loadUnit' => a('loadUnit'),
                        'numberFormat' => a('numberFormat'),
                        'currencyFormat' => a('currencyFormat'),
                        'costAccount' => a('costAccount'),
                        'revenueAccount' => a('revenueAccount'))

      firstCell = nil
      while t < @end
        # Create a new cell
        cell = newCell(line)

        # call TjTime::sameTimeNext... function
        nextT = t.send(sameTimeNextFunc)
        cellIv = Interval.new(t, nextT)
        # Get work load for all tasks.
        query.scopeProperty = nil
        query.attributeId = 'effort'
        query.startIdx = @project.dateToIdx(t, true)
        query.endIdx = @project.dateToIdx(nextT, true) - 1
        query.process
        workLoad = query.numericalResult
        scaledWorkLoad = query.result
        if task
          # Get work load for the particular task.
          query.scopeProperty = task
          query.process
          workLoadTask = query.numericalResult
          scaledWorkLoad = query.result
        else
          workLoadTask = 0.0
        end
        # Get unassigned work load.
        query.attributeId = 'freework'
        query.process
        freeLoad = query.numericalResult
        case columnDef.content
        when 'empty'
          # We only generate cells will different background colors.
        when 'load'
          # Report the workload of the resource in this time interval.
          # To increase readability, we don't show 0.0 values.
          wLoad = task ? workLoadTask : workLoad
          if wLoad > 0.0
            cell.text = scaledWorkLoad
          end
        else
          raise "Unknown column content #{column.content}"
        end

        # Determine cell category (mostly the background color)
        cell.category = if task
                          if cellIv.overlaps?(taskIv)
                            if workLoadTask > 0.0 && freeLoad == 0.0
                              'busy'
                            elsif workLoad == 0.0 && freeLoad == 0.0
                              'offduty'
                            else
                              'loaded'
                            end
                          else
                            if freeLoad > 0.0
                              'free'
                            elsif workLoad == 0.0 && freeLoad == 0.0
                              'offduty'
                            else
                              'resourcecell'
                            end
                          end
                        else
                          if workLoad > 0.0 && freeLoad == 0.0
                            'busy'
                          elsif workLoad > 0.0 && freeLoad > 0.0
                            'loaded'
                          elsif workLoad == 0.0 && freeLoad > 0.0
                            'free'
                          else
                            'offduty'
                          end
                        end
        cell.category += line.property.get('index') % 2 == 1 ? '1' : '2'

        tryCellMerging(cell, line, firstCell)

        t = nextT
        firstCell = cell unless firstCell
      end

      legend.addCalendarItem('Resource is fully loaded', 'busy1')
      legend.addCalendarItem('Resource is partially loaded', 'loaded1')
      legend.addCalendarItem('Resource is available', 'free')
      legend.addCalendarItem('Off duty time', 'offduty')
    end

    def setStandardCellAttributes(cell, columnDef, attributeType, line)
      # Determine whether it should be indented
      if indent(columnDef.id, attributeType)
        cell.indent = line.indentation
      end

      # Determine the cell alignment
      cell.alignment = alignment(columnDef.id, attributeType)

      # Set background color
      if line.property.is_a?(Task)
        cell.category = line.property.get('index') % 2 == 1 ?
          'taskcell1' : 'taskcell2'
      else
        cell.category = line.property.get('index') % 2 == 1 ?
          'resourcecell1' : 'resourcecell2'
      end
    end

    # Create a new ReportTableCell object and initialize some common values.
    def newCell(line, text = '')
      property = line.property
      cell = ReportTableCell.new(line, text)

      # Cells for containers should be using bold font face.
      cell.bold = true if property.container?

      cell
    end

    # Determine the indentation for this line.
    def setIndent(line, propertyRoot, treeMode)
      property = line.property
      scopeLine = line.scopeLine
      level = property.level - (propertyRoot ? propertyRoot.level : 0)
      # We indent at least as much as the scopeline + 1, if we have a scope.
      line.indentation = scopeLine.indentation + 1 if scopeLine
      # In tree mode we indent according to the level.
      line.indentation += level if treeMode
    end

    # Set the URL associated with the cell text. _cell_ is the ReportTableCell.
    # _columnDef_ is the user specified definition for the cell content and
    # look. _query_ is the query used to resolve dynamic macros in the cellURL.
    def setCellURL(cell, columnDef, query)
      return unless columnDef.cellURL

      url = expandMacros(columnDef.cellURL, cell.text, query)
      cell.url = url unless url.empty?
    end

    # Try to merge equal cells without text to multi-column cells.
    def tryCellMerging(cell, line, firstCell)
      if cell.text == '' && firstCell && (c = line.last(1)) && c == cell
        cell.hidden = true
        c.columns += 1
      end
    end

    # Expand the run-time macros in _pattern_. ${0} is a special case and will
    # be replaced with the _originalText_. For all other macros the _query_ will
    # be used with the macro name used for the attributeId of the query. The
    # method returns the expanded pattern.
    def expandMacros(pattern, originalText, query)
      return pattern unless pattern.include?('${')

      out = ''
      # Scan the pattern for macros ${...}
      i = 0
      while i < pattern.length
        c = pattern[i]
        if c == ?$
          # This could be a macro
          if pattern[i + 1] != ?{
            # It's not. Just append the '$'
            out << c
          else
            # It is a macro.
            i += 2
            macro = ''
            # Scan for the end '}' and get the macro name.
            while i < pattern.length && pattern[i] != ?}
              macro << pattern[i]
              i += 1
            end
            if macro == '0'
              # This turns RichText into plain ASCII!
              out += originalText
            else
              # resolve by query
              # If the macro is prefixed by a '?' it may be undefined.
              if macro[0] == ??
                macro = macro[1..-1]
                ignoreErrors = true
              else
                ignoreErrors = false
              end
              query.attributeId = macro
              query.process
              unless query.ok || ignoreErrors
                raise TjException.new, query.errorMessage
              end
              # This turns RichText into plain ASCII!
              out += query.result
            end
          end
        else
          # Just append the character to the output.
          out << c
        end
        i += 1
      end

      out
    end

  end

end
