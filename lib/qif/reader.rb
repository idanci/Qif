require 'stringio'
require 'qif/date_format'
require 'qif/transaction'

module Qif
  class Reader
    include Enumerable

    attr_reader :index

    SUPPORTED_ACCOUNTS = {
      "!Type:Bank" => "Bank account transactions",
      "!Type:Cash" => "Cash account transactions",
      "!Type:CCard" => "Credit card account transactions",
      "!Type:Oth A" => "Asset account transactions",
      "!Type:Oth L" => "Liability account transactions"
    }

    class UnknownAccountType < StandardError; end
    class UnrecognizedData < StandardError; end

    def initialize(data, format = nil)
      @data = data.respond_to?(:read) ? data : StringIO.new(data.to_s)
      @format = DateFormat.new(format || guess_date_format || 'dd/mm/yyyy')
      read_header
      raise(UnrecognizedData, "Provided data doesn't seems to represent a QIF file") unless @header
      raise(UnknownAccountType, "Unknown account type. Should be one of followings :\n#{SUPPORTED_ACCOUNTS.keys.inspect}") unless SUPPORTED_ACCOUNTS.keys.collect(&:downcase).include? @header.downcase
      reset
    end

    def transactions
      read_all_transactions
      transaction_cache
    end

    def each(&block)
      reset

      while transaction = next_transaction
        yield transaction
      end
    end

    # Return the number of transactions in the qif file.
    def size
      read_all_transactions
      transaction_cache.size
    end
    alias length size

    # Guess the file format of dates, reading the beginning of file, or return nil if no dates are found (?!).
    def guess_date_format
      begin
        line = @data.gets
        break if line.nil?

        date = line[1..-1]
        guessed_format = Qif::DateFormat::SUPPORTED_DATEFORMAT.find { |format_string, format|
          test_date_with_format?(date, format_string, format)
        }
      end until guessed_format

      @data.rewind
      guessed_format ? guessed_format.first : @fallback_format
    end

    private

    def test_date_with_format?(date, format_string, format)
      parsed_date = Date.strptime(date, format)
      if parsed_date > Date.strptime('01/01/1900', '%d/%m/%Y')
        @fallback_format ||= format_string
        parsed_date.day > 12
      end
    rescue
      false
    end

    def read_all_transactions
      while next_transaction; end
    end

    def transaction_cache
      @transaction_cache ||= []
    end

    def reset
      @index = -1
    end

    def next_transaction
      @index += 1

      if transaction = transaction_cache[@index]
        transaction
      else
        read_transaction
      end
    end

    def rewind_to(n)
      @data.rewind
      while @data.lineno != n
        @data.readline
      end
    end

    def read_header
      headers = []
      begin
        line = @data.readline.strip
        headers << line.strip if line =~ /^!/
      end until line !~ /^!/

      @header = headers.shift
      @options = headers.map{|h| h.split(':') }.last

      unless line =~ /^\^/
        rewind_to @data.lineno - 1
      end
      headers
    end

    def read_transaction
      if record = read_record
        transaction = Transaction.read(record)
        cache_transaction(transaction) if transaction
      end
    end

    def cache_transaction(transaction)
      transaction_cache[@index] = transaction
    end

    def read_record
      record = {}
      begin
        line = @data.readline
        key = line[0,1]
        record[key] = record.key?(key) ? record[key] + "\n" + line[1..-1].strip : line[1..-1].strip

        record[key].sub!(',','') if %w(T U $).include? key
        record[key] = @format.parse(record[key]) if %w(D).include? key

      end until line =~ /^\^/
      record
      rescue EOFError => e
        @data.close
        nil
      rescue Exception => e
        nil
    end
  end
end
