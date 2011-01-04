#!/usr/bin/ruby -w
# requires you to have previously run:
# gem install dbi
require 'rubygems'
require 'dbi'
puts "Loaded DBI #{DBI::VERSION}"

if ARGV.size != 5 && ARGV != 7
  puts ''
  puts 'usage: ss driver_url user pass column_name value [table_names_query] [column_names_query]'
  puts ''
  puts 'If column_names_query is defined, the table name should be defined as $TABLE_NAME.'
  
  puts 'examples:'
  puts 'MySQL: ss DBI:Mysql:TESTDB:localhost jdoe passwd user_id 1234'
  puts 'Oracle: ss DBI:OCI8://db.acme.org:1234/ACMETEST.WORLD jdoe passwd user_id 1234'
  puts 'Custom: ss DBI:OCI8://db.acme.org:1234/ACMETEST.WORLD jdoe passwd user_id 1234 "select TABLE_NAME from ALL_ALL_TABLES" "select column_name FROM all_tab_cols where table_name =\'$TABLE_NAME\'"'
  
  exit
end

driver_url = ARGV[0]
user = ARGV[1]
pass = ARGV[2]
column_name = ARGV[3]
value = ARGV[4]

table_names_query = nil
column_names_query = nil
if ARGV.size == 7
  table_names_query = ARGV[5]
  column_names_query = ARGV[6]
else
  # if you add support for something, please add it to the supported list in statement below
  if driver_url.upcase.match(/^DBI:OCI8/)
    # oracle
    table_names_query = 'select TABLE_NAME from ALL_ALL_TABLES'
    column_names_query = 'select name from SYSCOLUMNS where id=(select id from SYSOBJECTS where name=\'$TABLE_NAME\')'
    column_names_query = 'select column_name FROM all_tab_cols where table_name =\'$TABLE_NAME\''
  else
    puts ''
    puts 'You must specify table_names_query and column_names_query arguments for this driver_url.'
    puts ''
    puts 'ss DBI:OCI8://db.acme.org:1234/ACMETEST.WORLD jdoe passwd user_id 1234 "select TABLE_NAME from ALL_ALL_TABLES" "select column_name FROM all_tab_cols where table_name =\'$TABLE_NAME\'"'
    puts ''
    puts 'If column_names_query is defined, the table name should be defined as $TABLE_NAME.'
    puts ''
    puts 'Please submit a patch with the queries you figure out to make ss easier to use!'
    puts ''
    puts 'We currently have a table_names_query and column_names_query argument for driver urls starting with:'
    puts 'DBI:OCI8 (Oracle)'
    exit
  end
end

puts "driver_url=#{driver_url}"
puts "user=#{user}"
puts "pass=#{pass}"
puts "column_name=#{column_name}"
puts "value=#{value}"
puts "table_names_query=#{table_names_query}"
puts "column_names_query=#{column_names_query}"

def sleuth(dbh, table_names, column_names_query, column_name, value, excluded_data_pointers, stack)  
  if stack.size > 5
    stack.pop
    return
  end
  
  table_names.each do |this_table_name|
    specific_column_names_query = String.new(column_names_query)
    specific_column_names_query['$TABLE_NAME'] = this_table_name
    last_query = specific_column_names_query
    begin
      #puts specific_column_names_query
      column_names_rows = dbh.select_all(specific_column_names_query)
      column_names_rows.each do |column_name_row|
        this_column_name = column_name_row[0]
        if this_column_name.upcase.eql? column_name.upcase
          count_query = "select count(#{column_name}) from #{this_table_name} where #{column_name}=\'#{value}\'"
          last_query = count_query
          count_row = dbh.select_one(count_query)
          if count_row[0] && count_row[0].to_i > 1000
            #puts "skipping #{this_table_name}: (found #{count_row[0].to_i} rows matching, which exceeded maximum row count of 1000.)"
            #puts ''
            #puts ''
          else
            data_query = "select * from #{this_table_name} where #{column_name}=\'#{value}\'"
            last_query = data_query
            clue_rows = dbh.select_all(data_query)
            
            if (clue_rows.size > 0)
              #sorted_stack = stack.sort.join("\n")
              #puts "Stack:\n#{sorted_stack}"
              #puts ''
              #puts ''
              
              puts "#{this_table_name}"
              puts ''
              puts column_names_rows.collect {|column_names_row| column_names_row[0] }.join ', '
              puts '------------'
          
              clue_rows.each do |clue_row|
                puts clue_row.join ', '
              end
              puts ''
              puts ''
          
              clue_rows.each_with_index do |clue_row, clue_row_index|
                clue_row.each_with_index do |clue_row_column_value, clue_row_column_value_index|
                  if clue_row_column_value && clue_row_column_value.to_s.size > 0
                    clue_row_column_name = column_names_rows[clue_row_column_value_index][0]
                    #data_pointer = "#{this_table_name}:#{clue_row.join(', ')}"
                    data_pointer = "#{this_table_name}.#{clue_row_column_name}"
                    if !(excluded_data_pointers.include? data_pointer)
                      #sorted_list = excluded_data_pointers.sort.join("\n")
                      #puts "#{data_pointer}\nnot found in:\n#{sorted_list}"
                      excluded_data_pointers << data_pointer
                      #puts "Following #{data_pointer}"
                      
                      stack << "#{this_table_name}.#{clue_row_column_name} = '#{clue_row_column_value}'"
                  
                      sleuth(dbh, table_names, column_names_query, clue_row_column_name, clue_row_column_value, excluded_data_pointers, stack)
                    end
                  end
                end
              end
            end
          end
        end
      end
      
    rescue DBI::DatabaseError => e
      puts "A database error occurred while processing the query: #{last_query.to_s}"
      puts "Error code: #{e.err}"
      puts "Error message: #{e.errstr}"
    rescue
      puts "An error occurred #{e}"
    end
  end
  
  stack.pop
  return
end

table_names = []
begin
  #format for Oracle is DBI.connect('DBI:OCI8://host:port/service_name','username','password')
  dbh = DBI.connect(driver_url, user, pass)

  # get server version string and display it
  row = dbh.select_one('select version from v$instance')
  puts "Server version: #{row[0]}"
  
  puts ''
  puts table_names_query
  table_names_rows = dbh.select_all(table_names_query)
  puts "Tables: #{table_names_rows.inspect}"
  
  table_names_rows.each do |table_name_row|
    table_names << table_name_row[0]
  end
  
  sleuth(dbh, table_names, column_names_query, column_name, value, [], [])
  
rescue DBI::DatabaseError => e
  puts "An error occurred"
  puts "Error code: #{e.err}"
  puts "Error message: #{e.errstr}"
ensure
  # disconnect from server
  dbh.disconnect if dbh
end
