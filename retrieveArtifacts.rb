# Copyright (c) 2011, 2012, 2013, 2014, 2015 Solano Labs All Rights Reserved

# A very crude example of how to use the Solano CI JSON API to retrieve
# the list of files attached to a recent session.
#
# User must supply:
#
# 1. An API key, e.g. as produced with the ``solano login`` command (must be in
#    a file called .solano)
# 2. An endpoint URL for your Solano CI instance
# 3. An account handle; this identifies your account in your Solano CI instance
# 4. Origin URL to identify repository - must be an SSH URL
#    E.g. ssh://git@github.com/solanolabs/solano
# 5. A list of files you wish to fetch from the session
# 5. An optional branch in the repository
# 6. An optional build status to search for (e.g. most recent *passing* build)

require 'json'
require 'httpclient'
require 'shellwords'

API_VERSION = 1
API_KEY_HEADER = "X-Tddium-Api-Key"
CLIENT_VERSION_HEADER = "X-Tddium-Client-Version"

CLIENT_VERSION="0.4.4"

QUERY_LIMIT = 1
SOLANO_HOST = 'ci.solanolabs.com'
ACCOUNT_HANDLE = 'solanolabs'
ORIGIN_URL = 'ssh://git@github.com/solanolabs/ballin-dangerzone'
BRANCH = 'master'

FILE_LIST = ['file0.zip','file1.zip']

# Construct URI for API call
def solano_uri(path)
  uri = URI.parse("")
  uri.host = SOLANO_HOST
  uri.port = 443
  uri.scheme = 'https'
  URI.join(uri.to_s, "#{API_VERSION}/#{path}").to_s
end

# Read API key from .solano file produced by ``solano login``
def read_api_key
  path = nil
  if File.exists?('.solano') then
    path = '.solano'
  elsif File.exists?(File.join(ENV['HOME'], '.solano')) then
    path = File.join(ENV['HOME'], '.solano')
  end
  raise "unable to read API key" if path.nil?

  data = JSON.parse(File.read(path))
  return data['api_key']
end

# Make JSON API call
def call_api(method, api_path, params)
  api_key = read_api_key
  headers = {'Content-Type' => 'application/json',
             API_KEY_HEADER => api_key,
             CLIENT_VERSION_HEADER => "tddium-client_#{CLIENT_VERSION}"}
  client = HTTPClient.new
  http = client.send(method, solano_uri(api_path),
            :body => params.to_json, :header => headers)
  if http.code != 200 then
    raise "API Error"
  end
  response = JSON.parse(http.body) rescue {}
  if response['status'] != 0 then
    raise "API Error: #{response['explanation']}"
  end
  return response
end

# Look up ID for a branch in a repository
params = {:repo_url => ORIGIN_URL, :branch => BRANCH}
result = call_api(:get, '/suites/user_suites', params)
suites_list = result['suites']
suite = suites_list.select { |suite| suite['account'] == ACCOUNT_HANDLE }.first
if suite.nil? then
  raise "Branch #{BRANCH} not found for repo #{ORIGIN_URL} in account #{ACCOUNT_HANDLE}"
end
suite_id = suite['id']

# Look up list of sessions for repository or branch
params = {:suite_id => suite_id,
          :status => 'passed',             # omit to get all sessions
          :active => false,                # completed sessions only
          :origin => 'ci',                 # only CI sessions
          :limit => QUERY_LIMIT}
result = call_api(:get, '/sessions', params)

session_list = result['sessions']
session_list.sort! do |sa, sb|
  sb['id'] <=> sa['id']
end

# Look up data for each session in the list
# Find first passing session (if any) and use it

passing_session = nil
session_list.each do |session_summary|
  result = call_api(:get, "/sessions/#{session_summary['id']}", {})
  session = result['session']
  if session['summary_status'] == 'passed' then
    passing_session = session
    break
  end
end

if passing_session.nil? then
  abort "No recent passing sessions on branch"
end

file_links = passing_session['file_links']
if file_links.empty? then
  abort "No files attached to Session #{passing_session['id']}"
end

files_found = 0
file_links.each do |file_data|
  # Name is the file name of the file attached to the build
  # URL is an authenticated URL and has required query parameters
  # Description is a short human-readable description of the file
  name, url, description = file_data
  if FILE_LIST.include? name then		# Select which files to download
    files_found += 1
    puts "curl -o #{name} #{Shellwords.escape(url)}"
  end
end

if files_found == 0 then
  abort "No files matching pattern found in Session #{passing_session['id']}"
end
