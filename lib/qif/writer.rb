require 'qif/date_format'
require 'qif/transaction'

module Qif
  class Writer
    attr_accessor :type, :format

    def self.open(path, type = 'Bank', format = 'dd/mm/yyyy', &block)
      File.open(path, 'w') do |file|
        self.new(file, type, format, &block)
      end
    end

    def initialize(io, type = 'Bank', format = 'dd/mm/yyyy')
      @io = io.respond_to?(:write) ? io : File.open(io, 'w')
      @type = type
      @format = format
      @transactions = []

      if block_given?
        yield self
        self.write
      end
    end

    def <<(transaction)
      @transactions << transaction
    end

    def write
      write_header
      write_transactions
    end

    def close
      @io.close
    end

    private

    def write_header
      @io.write("!Type:%s\n" % @type)
    end

    def write_transactions
      @transactions.each do |t|
        write_transaction(t)
      end
    end

    def write_transaction(transaction)
      write_record(transaction.to_s(@format))
    end

    def write_record(data)
      @io.write(data)
      @io.write("\n^\n")
    end
  end
end
