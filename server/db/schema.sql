\restrict dbmate

-- Dumped from database version 17.5
-- Dumped by pg_dump version 18.1

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: set_tile(integer, integer, integer, integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.set_tile(IN x_ integer, IN y_ integer, IN color_ integer, IN user_id_ integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
  width_ INTEGER;
  height_ INTEGER;
  max_color_ INTEGER;
BEGIN
    SELECT width, height, max_color INTO width_, height_, max_color_ FROM board_config;

    IF color_ < 0 OR color_ > max_color_ THEN
      RAISE EXCEPTION 'Expected: 0-%, got: %', max_color_, color_;
    END IF;

    IF x_ < 0 OR x_ >= width_ OR y_ < 0 OR y_ >= height_ THEN
      RAISE EXCEPTION 'Coordinates out of bounds: (%, %)', x_, y_;
    END IF;

    UPDATE board
    SET color = color_, updated_by = user_id_
    WHERE x = x_ AND y = y_;

    INSERT INTO board_history (x, y, color, user_id)
    VALUES (x_, y_, color_, user_id_);
END;
$$;


--
-- Name: update_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  new.updated_at = NOW() at time zone 'utc';
  return new;
end
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: board; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.board (
    x integer NOT NULL,
    y integer NOT NULL,
    color integer NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_by integer
);


--
-- Name: board_config; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.board_config (
    id integer DEFAULT 1 NOT NULL,
    width integer NOT NULL,
    height integer NOT NULL,
    max_color integer NOT NULL,
    CONSTRAINT board_config_check CHECK (((width > 0) AND (height > 0))),
    CONSTRAINT board_config_id_check CHECK ((id = 1)),
    CONSTRAINT board_config_max_color_check CHECK ((max_color >= 0))
);


--
-- Name: board_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.board_history (
    id bigint NOT NULL,
    x integer NOT NULL,
    y integer NOT NULL,
    color integer NOT NULL,
    user_id integer,
    created_at timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: board_history_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.board_history ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.board_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    id integer NOT NULL,
    token_hash bytea NOT NULL,
    user_id integer NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    expires_at timestamp without time zone NOT NULL
);


--
-- Name: sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.sessions ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id integer NOT NULL,
    email public.citext NOT NULL,
    password_hash text NOT NULL,
    username text NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.users ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: board_config board_config_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.board_config
    ADD CONSTRAINT board_config_pkey PRIMARY KEY (id);


--
-- Name: board_history board_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.board_history
    ADD CONSTRAINT board_history_pkey PRIMARY KEY (id);


--
-- Name: board board_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.board
    ADD CONSTRAINT board_pkey PRIMARY KEY (x, y);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: sessions sessions_token_hash_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_token_hash_key UNIQUE (token_hash);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: users users_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);


--
-- Name: sessions_user_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sessions_user_id_idx ON public.sessions USING btree (user_id);


--
-- Name: board board_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER board_updated_at BEFORE UPDATE OF color, updated_by ON public.board FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: users users_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER users_updated_at BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: board_history board_history_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.board_history
    ADD CONSTRAINT board_history_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: board board_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.board
    ADD CONSTRAINT board_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: sessions sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- PostgreSQL database dump complete
--

\unrestrict dbmate


--
-- Dbmate schema migrations
--

INSERT INTO public.schema_migrations (version) VALUES
    ('20260130021931'),
    ('20260130040157'),
    ('20260130042327'),
    ('20260130211710'),
    ('20260319212640'),
    ('20260320042714'),
    ('20260320200609'),
    ('20260321181005');
