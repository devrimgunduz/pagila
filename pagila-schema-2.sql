-- Create sequence for streaming_activity_id
CREATE SEQUENCE public.streaming_activity_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

-- Create the streaming_activity table
CREATE TABLE public.streaming_activity (
                                           activity_id integer DEFAULT nextval('public.streaming_activity_id_seq'::regclass) NOT NULL,
                                           session_id uuid DEFAULT gen_random_uuid() NOT NULL,
                                           film_id integer,  -- Optional reference to existing films
                                           customer_id integer, -- Optional reference to existing customers
                                           view_count bigint DEFAULT 0 NOT NULL,
                                           stream_start_time time NOT NULL,
                                           watch_duration interval NOT NULL,
                                           playback_position double precision DEFAULT 0.0 NOT NULL,
                                           player_settings jsonb NOT NULL,
                                           created_at timestamp with time zone DEFAULT now() NOT NULL,
                                           last_update timestamp with time zone DEFAULT now() NOT NULL
);

-- Add primary key
ALTER TABLE ONLY public.streaming_activity
    ADD CONSTRAINT streaming_activity_pkey PRIMARY KEY (activity_id);

-- Add index on session_id
CREATE INDEX idx_streaming_activity_session_id ON public.streaming_activity(session_id);

-- Add trigger for last_updated
CREATE TRIGGER last_updated
    BEFORE UPDATE ON public.streaming_activity
    FOR EACH ROW
EXECUTE FUNCTION public.last_updated();

-- Add optional foreign key constraints if needed
-- ALTER TABLE ONLY public.streaming_activity
--     ADD CONSTRAINT streaming_activity_film_id_fkey FOREIGN KEY (film_id) REFERENCES public.film(film_id) ON UPDATE CASCADE ON DELETE RESTRICT;
-- ALTER TABLE ONLY public.streaming_activity
--     ADD CONSTRAINT streaming_activity_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customer(customer_id) ON UPDATE CASCADE ON DELETE RESTRICT;

-- Grant permissions
ALTER TABLE public.streaming_activity OWNER TO postgres;


-- Create custom types for media-specific enums
CREATE TYPE public.video_codec AS ENUM (
    'H264',
    'H265',
    'VP9',
    'AV1',
    'MPEG2',
    'MPEG4'
    );

CREATE TYPE public.audio_channel_config AS ENUM (
    'MONO',
    'STEREO',
    'SURROUND_5_1',
    'SURROUND_7_1',
    'DOLBY_ATMOS'
    );

-- Create composite type for color information
CREATE TYPE public.color_info AS (
                                     color_space text,
                                     bit_depth smallint,
                                     color_primaries text
                                 );

-- Create the comprehensive test table
CREATE TABLE public.media_technical_metadata (
    -- Identifier columns
                                                 metadata_id bigserial PRIMARY KEY,                        -- Test bigint auto-increment
                                                 content_id uuid DEFAULT gen_random_uuid(),                -- Test UUID type

    -- Numeric types
                                                 file_size_bytes bigint,                                   -- Test bigint
                                                 video_bitrate integer,                                    -- Test integer
                                                 audio_bitrate smallint,                                   -- Test smallint
                                                 average_framerate real,                                   -- Test real/float4
                                                 actual_framerate double precision,                        -- Test double precision/float8
                                                 quality_score numeric(5,2),                               -- Test numeric with precision
                                                 peak_bitrate decimal,                                     -- Test decimal
                                                 monetary_cost money,                                      -- Test money type

    -- Character types
                                                 title character varying(255),                             -- Test varchar
                                                 description text,                                         -- Test text
                                                 content_hash character(64),                               -- Test char fixed-length

    -- Date/Time types
                                                 created_timestamp timestamp,                              -- Test timestamp
                                                 created_timestamp_tz timestamp with time zone,            -- Test timestamp with timezone
                                                 last_modified_date date,                                  -- Test date
                                                 duration interval,                                        -- Test interval
                                                 preferred_viewing_time time,                              -- Test time
                                                 preferred_viewing_time_tz time with time zone,            -- Test time with timezone

    -- Binary data
                                                 thumbnail_image bytea,                                    -- Test bytea

    -- Boolean type
                                                 is_drm_protected boolean,                                 -- Test boolean

    -- Network address types
                                                 cdn_primary_ip inet,                                      -- Test inet
                                                 cdn_subnet cidr,                                          -- Test cidr
                                                 mac_address macaddr,                                      -- Test macaddr
                                                 mac_address_8 macaddr8,                                   -- Test macaddr8

    -- Geometric types
                                                 video_dimensions point,                                   -- Test point
                                                 safe_area_box box,                                        -- Test box
                                                 crop_polygon polygon,                                     -- Test polygon
                                                 camera_path path,                                         -- Test path
                                                 subtitle_positions line,                                  -- Test line

    -- JSON types
                                                 player_config json,                                       -- Test json
                                                 stream_settings jsonb,                                    -- Test jsonb

    -- XML type
                                                 metadata_xml xml,                                         -- Test xml

    -- Bit string types
                                                 feature_flags bit(8),                                     -- Test fixed-length bit
                                                 extended_flags bit varying(32),                           -- Test variable-length bit

    -- Array types
                                                 audio_languages text[],                                   -- Test text array
                                                 subtitle_languages text[],                                -- Test another array type
                                                 quality_scores integer[],                                 -- Test integer array
                                                 segment_durations numeric(5,2)[],                         -- Test numeric array

    -- Range types
                                                 buffered_ranges int4range,                               -- Test integer range
                                                 saturation_range int8range,                              -- Test bigint range
                                                 temporal_range tsrange,                                   -- Test timestamp range
                                                 temporal_range_tz tstzrange,                             -- Test timestamp with timezone range
                                                 date_availability daterange,                              -- Test date range
                                                 numeric_range numrange,                                   -- Test numeric range

    -- Custom enum types
                                                 video_codec video_codec,                                  -- Test enum type
                                                 audio_channels audio_channel_config,                      -- Test another enum type

    -- Composite type
                                                 color_information color_info,                            -- Test composite type

    -- Domain types
                                                 release_year year,                                       -- Test existing year domain from Pagila

    -- Additional special types
                                                 search_document tsvector,                                -- Test full text search vector
                                                 search_query tsquery,                                    -- Test full text search query

    -- Constraint examples
                                                 CONSTRAINT valid_video_bitrate CHECK (video_bitrate > 0),
                                                 CONSTRAINT valid_audio_bitrate CHECK (audio_bitrate > 0)
);

-- Create indexes for commonly queried fields
CREATE INDEX idx_media_content_id ON public.media_technical_metadata(content_id);
CREATE INDEX idx_media_title ON public.media_technical_metadata(title);
CREATE INDEX idx_media_search ON public.media_technical_metadata USING GIN(search_document);

-- Grant appropriate permissions
ALTER TABLE public.media_technical_metadata OWNER TO postgres;