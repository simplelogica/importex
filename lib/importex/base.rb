module Importex
  class Base

    attr_reader :attributes
    attr_reader :row_number
    attr_accessor :errors
    attr_reader :translated_object

    # Defines a column that may be found in the excel document. The first argument is a string
    # representing the name of the column. The second argument is a hash of options.
    #
    # Options:
    # [:+type+]
    #   The Ruby class to be used as the value on import.
    #
    #     column :type => Date
    #
    # [:+format+]
    #   Usually a regular expression representing the required format for the value. Can also be a string
    #   or an array of strings and regular expressions.
    #
    #     column :format => [/^\d+$/, "0.0"]
    #
    # [:+required+]
    #   Boolean specifying whether or not the given column must be present in the Excel document.
    #   Defaults to false.
    def self.column(*args)
      self.cattr_accessor :columns
      self.columns ||= []
      self.columns << Column.new(*args)
    end

    # Pass a path to an Excel (xls) document and optionally the worksheet index. The worksheet
    # will default to the first one (0). The first row in the Excel document should be the column
    # names, all rows after that should be records.
    def self.import(path, worksheet_index = 0)
      @records = []
      workbook = Spreadsheet.open(path)
      worksheet = workbook.worksheet(worksheet_index)
      worksheet_columns = worksheet.row(0)

      columns = worksheet.row(0).map do |cell|
        self.columns.detect { |column| column.name == cell.to_s }
      end

      missing_columns = self.columns.select(&:required?) - columns

      raise MissingColumn, "Columns #{missing_columns.map{|c| "'#{c.name}'"}.join(", ")} is/are required but it doesn't exist in #{worksheet_columns.map{|c| "'#{c.to_s}'"}.join(", ")}." unless missing_columns.blank?

      (1...worksheet.row_count).each do |row_number|

        row = worksheet.row(row_number)

        # If this row has no cell with content we don't use it
        # This way we skip blank rows without content that only has styles
        if row.detect{|cell| !cell.nil?}
          attributes = {:row_number => row_number}
          errors = {}
          record = new(attributes)
          columns.each_with_index do |column, index|
            if column
              if row.at(index).nil?
                value = ""
              elsif row.at(index).class == :date
                value = row.at(index).date.strftime("%Y-%m-%d %H:%M:%I")
              else
                value = row.at(index)
              end

              if column.valid_cell?(value, record)
                attributes[column.name] = column.cell_value(value)
              else
                errors[column.name.downcase.to_sym] = column.errors
              end

            end
          end

          record.errors = errors
          @records << record
        end
      end

      if self.respond_to? :validate_all
        self.validate_all
      end

      @records

    end

    # Returns all records imported from the excel document.
    def self.all
      @records
    end

    # Returns all records imported from the excel document with errors.
    def self.invalid
      @records.reject{|r| r.errors.blank?}
    end


    # Returns all records imported from the excel document with errors.
    def self.valid
      @records.select{|r| r.errors.blank?}
    end

    def initialize(attributes = {})
      @row_number = attributes.delete(:row_number)
      @attributes = attributes
    end

    # A convenient way to access the column data for a given record.
    #
    #   product["Price"]
    #
    def [](name)
      @attributes[name]
    end

    # This methods register to which class we umust translate this one
    def self.translate_to(class_name, options={})

      self.cattr_accessor :translated_class
      self.cattr_accessor :after_translate
      self.cattr_accessor :initialize_translated_object

      self.translated_class = class_name.constantize
      self.after_translate = options[:after]
      self.initialize_translated_object = options[:initialize]
    end

    # This methods translates all (valid and invalid) records
    def self.translate_all
      translate all
    end

    # This methods translates valid records
    def self.translate_valid
      translate valid
    end

    # This methods translates invalid records
    def self.translate_invalid
      translate invalid
    end

    # And this method performs translation to a single row
    # Right now, for each column we fall into the default column behaviour
    def translate

      @translated_object = self.initialize_translated_object.nil? ?
        self.translated_class.new :
        initialize_translated_object.call(self)

      self.columns.each do |column|
        column.translate translated_object, self
      end
      @translated_object

    end

    protected

    def self.translate records

      # First we translate the records
      records.each(&:translate)
      # Then we execute the after Proc in case we need some extra computing
      self.after_translate.call(records) unless self.after_translate.nil?
      # And now we return the translated objects
      records.map(&:translated_object)

    end

  end
end
