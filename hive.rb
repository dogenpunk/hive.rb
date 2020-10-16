#!/usr/bin/env ruby

require 'rubygems'
require 'securerandom'
require 'sinatra'
require 'haml'
require 'json'
require 'pg'

configure :production do
  set :user, ENV['ADMIN_USER']
  set :password, ENV['ADMIN_PASSWORD']
  set :dbhost, ENV['DATABASE_HOST']
  set :dbname, ENV['DATABASE_NAME']
  set :dbuser, ENV['DATABASE_USER']
  set :dbpass, ENV['DATABASE_PASSWORD']
end

configure :development do
  require 'pry'
  set :user, 'admin'
  set :password, 'admin'
  set :dbhost, 'localhost'
  set :dbname, 'hiveapp'
  set :dbuser, 'hiveappuser'
  set :dbpass, 'hiveappuser'
end

Post = Struct.new(:id, :content, :created_at, :updated_at, keyword_init: true)

class BadRequest < StandardError
  def http_status; 400 end
end

class Unauthorized < StandardError
  def http_status; 401 end
end

class PermissionDenied < StandardError
  def http_status; 403 end
end

class NotFound < StandardError
  def http_status; 404 end
end

class UnsupportedMediaType < StandardError
  def http_status; 415 end
end

class InternalServerError < StandardError
  def http_status; 500 end
end

helpers do

  def protected!
    return if authorized?
    headers['WWW-Authenticate'] = 'Basic realm="Restricted Area"'
    raise Unauthorized, "Not authorized"
  end

  def authorized?
    @auth ||= Rack::Auth::Basic::Request.new(request.env)
    @auth.provided? and @auth.basic? and @auth.credentials and @auth.credentials == [settings.user, settings.password]
  end

  def with_connection
    begin
      conn = PG.connect dbname: settings.dbname, user: settings.dbuser, password: settings.dbpass
      return yield conn

    rescue PG::Error => e
      raise InternalServerError, "A service error occurred: #{e.to_s}"
    ensure
      conn.close if conn
    end
  end

  def validate! post
    ["Content cannot be nil."] if post.content.nil?
  end

  def persist! post
    sql = <<-SQL
    INSERT INTO posts (id, content)
    VALUES ($1::uuid, $2::text)
    RETURNING *
    ON CONFLICT (id)
    DO
      UPDATE SET content = EXCLUDED.content;
SQL
    results = nil
    with_connection do |conn|
      conn.transaction do |c|
        results = c.exec_params sql, [Post.id || SecureRandom.uuid, Post.content]
      end
    end

    results.nil? ? results : Post.new([:id, :content, :created_at, :updated_at].zip(results).to_h)
  end

  def hydrate id
    sql = <<-SQL
    SELECT id, content, created_at, updated_at
    FROM posts
    WHERE id = $1::uuid;
SQL
    results = nil
    with_connection do |conn|
      results = conn.exec_params sql, [id]
    end

    results.nil? ? results : Post.new([:id, :content, :created_at, :updated_at].zip(results).to_h)
  end

  def get_recent_posts
    sql = <<-SQL
    SELECT id, content, created_at, updated_at
    FROM posts
    ORDER BY updated_at DESC
    LIMIT 10;
SQL
    results = with_connection do |conn|
      conn.exec sql
    end

    results.each do |post|
      Post.new([:id, :content, :created_at, :updated_at].zip(post).to_h)
    end
  end
end

before do
  content_type :json
  cache_control
end

get '/' do
  content_type :html
  @recent = get_recent_posts
  haml :index
end

get '/about' do
  content_type :html
  haml :about
end

get '/contact' do
  content_type :html
  haml :contact
end

not_found do
  raise NotFound, 'The resource you\'re looking for is not here.'
end

post '/new' do
  protected!
  raise UnsupportedMediaType unless request.env['CONTENT_TYPE'] == 'application/json'

  begin
    blog_post = JSON.parse(request.body.read)
  rescue JSON::ParserError => e
    content_type :json
    halt 400, { message: e.to_s }.to_json
  end

  if (errors = invalid?(blog_post))
    halt 400, { errors: errors }.to_json
  end

  new_blog_post = persist!(blog_post)
  url = "/#{new_blog_post.id}"
  response.headers['Location'] = url

  status 201
end

get '/:id' do |id|
  @post = hydrate!(id)
  raise NotFound unless @post

  last_modified @post.updated_at
  etag @page.content
  @post.to_json
end

put '/:id' do |id|
  protected!
  raise UnsupportedMediaType unless request.env['CONTENT_TYPE'] == 'application/json'

  begin
    new_blog_post = JSON.parse(request.body.read)
  rescue JSON::ParserError => e
    content_type :json
    halt 400, { message: e }.to_json
  end

  if (errors = validate!(new_blog_post))
    content_type :json
    halt 400, { errors: errors }.to_json
  end

  if existing = hydrate!(id)
    persist!(merge_posts(existing, new_blog_post))

    content_type :json
    status 204
  else
    persist!(new_blog_post)
    
    content_type :json
    status 201
  end
end

delete '/:id' do |id|
  protected!
  blog_post = hydrate!(id)

  raise NotFound unless blog_post

  delete!(blog_post)
  status 204
end

__END__

@@ layout
!!! 5
%html(lang='en')
  %head
    %meta(charset='utf-8')
    %meta(name='viewport' content='width=device-width, initial-scale=1')
    %meta(http-equiv='X-UA-Compatible' content='IE=edge')

    %title 'QuAD Microblog'
    %meta(name='description' content='The home of thoughts random and pertinent.')

  %body
    #wrapper
      %header
        %h1 A Quick and Dirty Microblog
        %nav
          %ul
            %a(href='/')
              %li Home
            %a(href='/about')
              %li About
            %a(href='/contact')
              %li Contact

    #main
      != yield

    #side_bar

    #footer
      %p
        &copy; 2020 Matthew M. Nelson


@@ index
- @recent.each do |post|
  %article
    %p= post.content
    %span.created_at= post.created_at
end
%form{action: '/', method: 'POST'}
  %input{type: 'textarea', name: 'content'}
  %button{type: 'submit', name: 'New Post'}

@@ about
%p
  I put this application together in an evening to reaquaint myself
  with Ruby and Sinatra. I wanted to see how close I could get to having
  a reasonably useful application running on Heroku with as few files as possible.

@@ contact
%p
  My name is Matthew M. Nelson (I only use the initial as there's another, more
  famous, Matthew Nelson in my town). I'm an independent software developer and
  consultant.

@@ error
%h1 @env['sinatra.error'].http_status
%p
  @env['sinatra.error'].message
