require 'bundler/setup'
$:.unshift File.expand_path('../lib', __FILE__)

# rake spec
require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec) { |t| t.verbose = false   }

# rake console
task :console do
  require 'pry'
  require 'gem_name'
  ARGV.clear
  Pry.start
end

def with_connection
  begin
    conn = PG.connect host: ENV['DATABASE_HOST'],
                      dbname: ENV['DATABASE_NAME'],
                      user: ENV['DATABASE_USER'],
                      password: ENV['DATABASE_PASSWORD']
    return yield conn
  rescue PG::Error => e
  ensure
    conn.close if conn
  end

end

def migrate!
  sql = <<-SQL
CREATE TABLE IF NOT EXISTS posts (
  id SERIAL NOT NULL PRIMARY KEY,
  post_id UUID UNIQUE NOT NULL,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW());

CREATE OR REPLACE FUNCTION trigger_set_timestamp()
  RETURNS TRIGGER LANGUAGE 'plpgsql'
  AS $BODY$
    BEGIN
      NEW.updated_at = NOW();
      RETURN NEW;
    END
  $BODY$;

  DO $$
    BEGIN
      IF NOT EXISTS(SELECT *
        FROM information_schema.triggers
        WHERE event_object_table = 'posts'
        AND trigger_name = 'set_timestamp')
      THEN
        CREATE TRIGGER set_timestamp
          BEFORE UPDATE ON posts
          FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();
      END IF;
    END;
  $$
SQL
  results = with_connection do |conn|
    conn.exec sql
  end
end
