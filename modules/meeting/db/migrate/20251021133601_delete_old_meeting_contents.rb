# frozen_string_literal: true

class DeleteOldMeetingContents < ActiveRecord::Migration[8.0]
  def up
    execute("DROP TABLE meeting_contents")
    execute("DROP TABLE meeting_content_journals")
  end

  def down
    # create table with empty content
    # instructions copied from db/structure.sql of a release/16.6
    execute(<<~SQL.squish)
      CREATE TABLE meeting_content_journals (
          id bigint NOT NULL,
          meeting_id bigint,
          author_id bigint,
          text text,
          locked boolean
      );
      CREATE SEQUENCE meeting_content_journals_id_seq
          START WITH 1
          INCREMENT BY 1
          NO MINVALUE
          NO MAXVALUE
          CACHE 1;
      ALTER SEQUENCE meeting_content_journals_id_seq OWNED BY meeting_content_journals.id;

      CREATE TABLE meeting_contents (
          id bigint NOT NULL,
          type character varying,
          meeting_id bigint,
          author_id bigint,
          text text,
          lock_version integer,
          created_at timestamp with time zone NOT NULL,
          updated_at timestamp with time zone NOT NULL,
          locked boolean DEFAULT false
      );
      CREATE SEQUENCE meeting_contents_id_seq
          START WITH 1
          INCREMENT BY 1
          NO MINVALUE
          NO MAXVALUE
          CACHE 1;
      ALTER SEQUENCE meeting_contents_id_seq OWNED BY meeting_contents.id;

      ALTER TABLE ONLY meeting_content_journals ALTER COLUMN id SET DEFAULT nextval('meeting_content_journals_id_seq'::regclass);
      ALTER TABLE ONLY meeting_contents ALTER COLUMN id SET DEFAULT nextval('meeting_contents_id_seq'::regclass);

      ALTER TABLE ONLY meeting_content_journals
          ADD CONSTRAINT meeting_content_journals_pkey PRIMARY KEY (id);
      ALTER TABLE ONLY meeting_contents
          ADD CONSTRAINT meeting_contents_pkey PRIMARY KEY (id);
    SQL
  end
end
