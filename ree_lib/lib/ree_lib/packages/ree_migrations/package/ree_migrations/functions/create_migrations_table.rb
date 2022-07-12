# frozen_string_literal: true

class ReeMigrations::CreateMigrationsTable
  include Ree::FnDSL

  fn :create_migrations_table do
    singleton
    after_init :setup
  end

  def setup
    Sequel.extension(:migration)
  end

  contract(Sequel::Database => nil)
  def call(connection)
    if !connection.tables.include?(:migrations)
      connection[
        %Q(
          CREATE TABLE migrations (
            "filename" text PRIMARY KEY,
            "created_at" TIMESTAMP NOT NULL,
            "type" VARCHAR(8)
          )
        )
      ].all
    end

    nil
  end
end