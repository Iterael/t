#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = RTPReport.rb -- The TaskJuggler III Project Management Software
#
# Copyright (c) 2006, 2007, 2008, 2009 by Chris Schlaeger <cs@kde.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#

require 'RichTextProtocolHandler'
require 'XMLElement'

class TaskJuggler

  # This class is a specialized RichTextProtocolHandler that includes a
  # report into the RichText output for supported formats.
  class RTPReport < RichTextProtocolHandler

    def initialize(project, sourceFileInfo)
      super(project, 'report', sourceFileInfo)
    end

    # Not supported for this protocol
    def to_s(args)
      ''
    end

    # Return a HTML tree for the report.
    def to_html(args)
      if args.nil? || (id = args['id']).nil?
        error('rtp_report_id',
              "Argument 'id' missing to specify the report to be used.")
      end
      unless (report = @project.report(id))
        error('rtp_report_unknown_id', "Unknown report #{id}")
      end

      # Save the old report context record
      oldReportContext = @project.reportContext
      # Create a new context for the report.
      @project.reportContext = ReportContext.new(@project, report)
      # Generate the report with the new context
      report.generate
      html = report.to_html
      # Restore the global report context record again.
      @project.reportContext = oldReportContext

      html
    end

    # Not supported for this protocol.
    def to_tagged(args)
      nil
    end

  end

end
