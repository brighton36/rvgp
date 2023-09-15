# frozen_string_literal: true

class DuplicateTagsValidation < RRA::JournalValidationBase
  def validate
    journal = RRA::Journal.parse(File.open(transformer.output_file).read)
    dupe_messages = []

    journal.postings.each do |posting| 
      posting_tag_names = posting.tags.collect(&:key)
      found_dupes = posting_tag_names.find_all{ |tag| 
        posting_tag_names.count(tag) > 1 }.uniq

      if found_dupes.length > 0
        dupe_messages << 'Line %d: %s %s (%s)' % [ posting.line_number, 
          posting.date, posting.description, found_dupes.join(',') ]
      else
        posting.transfers.each{|transfer| 
          transfer_tag_names = transfer.tags.collect(&:key)+posting_tag_names

          found_dupes = transfer_tag_names.find_all{ |tag| 
            transfer_tag_names.count(tag) > 1 }.uniq

          dupe_messages << 'Line %d: %s %s (Transfer: %s)' % [
            posting.line_number, posting.date, posting.description,
            found_dupes.join(', ') ] if found_dupes.length > 0
        }
      end
    end

    error! "These postings have been tagged with the same tag, more than once",
      dupe_messages if dupe_messages.length > 0
  end
end
