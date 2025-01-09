-- Function to generate random bytea data
CREATE OR REPLACE FUNCTION generate_random_bytea(length integer) RETURNS bytea AS $$
DECLARE
    result bytea;
BEGIN
    SELECT decode(string_agg(lpad(to_hex(width_bucket(random(), 0, 1, 256)-1), 2, '0'), ''), 'hex')
    INTO result
    FROM generate_series(1, length);
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Insert first 50 rows
WITH numbered_rows AS (
    SELECT generate_series(1, 50) AS i
)
INSERT INTO public.media_technical_metadata (
    content_id,
    file_size_bytes,
    video_bitrate,
    audio_bitrate,
    average_framerate,
    actual_framerate,
    quality_score,
    peak_bitrate,
    monetary_cost,
    title,
    description,
    content_hash,
    created_timestamp,
    created_timestamp_tz,
    last_modified_date,
    duration,
    preferred_viewing_time,
    preferred_viewing_time_tz,
    thumbnail_image,
    is_drm_protected,
    cdn_primary_ip,
    cdn_subnet,
    mac_address,
    mac_address_8,
    video_dimensions,
    safe_area_box,
    crop_polygon,
    camera_path,
    subtitle_positions,
    player_config,
    stream_settings,
    metadata_xml,
    feature_flags,
    extended_flags,
    audio_languages,
    subtitle_languages,
    quality_scores,
    segment_durations,
    buffered_ranges,
    saturation_range,
    temporal_range,
    temporal_range_tz,
    date_availability,
    numeric_range,
    video_codec,
    audio_channels,
    color_information,
    release_year,
    search_document,
    search_query
)
SELECT
    gen_random_uuid(),
    -- Smaller file sizes
    CASE (i % 4)
        WHEN 0 THEN i * 1000000  -- 1MB increments
        WHEN 1 THEN 1000000     -- 1MB fixed
        WHEN 2 THEN NULL
        ELSE 100000000         -- 100MB max
        END,
    -- More reasonable video bitrates
    CASE (i % 3)
        WHEN 0 THEN 5000 + (i * 100)  -- 5-10Mbps range
        WHEN 1 THEN 15000             -- 15Mbps fixed
        ELSE 8000                      -- 8Mbps fixed
        END,
    -- Standard audio bitrates
    CASE (i % 3)
        WHEN 0 THEN 128
        WHEN 1 THEN 256
        ELSE 384
        END,
    -- Standard framerates
    CASE (i % 4)
        WHEN 0 THEN 23.976
        WHEN 1 THEN 29.97
        WHEN 2 THEN 59.94
        ELSE NULL
        END,
    -- Actual framerates (slightly off from nominal)
    CASE (i % 4)
        WHEN 0 THEN 23.976
        WHEN 1 THEN 29.970
        WHEN 2 THEN 59.940
        ELSE NULL
        END,
    -- Quality scores
    CASE (i % 5)
        WHEN 0 THEN 98.76
        WHEN 1 THEN 88.32
        WHEN 2 THEN 99.99
        WHEN 3 THEN NULL
        ELSE 50.00
        END,
    -- Peak bitrate
    CASE (i % 3)
        WHEN 0 THEN 15000
        WHEN 1 THEN 25000
        ELSE NULL
        END,
    -- Money values
    CASE (i % 4)
        WHEN 0 THEN '$0.00'::money
        WHEN 1 THEN '$99.99'::money
        WHEN 2 THEN '$999.99'::money
        ELSE NULL
        END,
    'Media Title ' || i,
    'Description for item ' || i || ' - Standard definition video',
    rpad(md5(i::text), 64, '0'),
    '2024-01-01'::timestamp + (i || ' days')::interval,
    '2024-01-01 UTC'::timestamptz + (i || ' days')::interval,
    '2024-01-01'::date + (i || ' days')::interval,
    make_interval(hours := (i % 4) + 1),  -- 1 to 4 hours duration
    '12:00:00'::time + ((i % 60) || ' minutes')::interval,
    '12:00:00 UTC'::timetz + ((i % 60) || ' minutes')::interval,
    generate_random_bytea(100),
    i % 2 = 0,
    CASE (i % 3)
        WHEN 0 THEN ('192.168.1.' || (i % 255))::inet
        WHEN 1 THEN NULL
        ELSE '10.0.0.1'::inet
        END,
    CASE (i % 3)
        WHEN 0 THEN '192.168.0.0/24'::cidr
        WHEN 1 THEN NULL
        ELSE '10.0.0.0/8'::cidr
        END,
    CASE (i % 3)
        WHEN 0 THEN '08:00:2b:01:02:03'::macaddr
        WHEN 1 THEN NULL
        ELSE 'f4:ce:46:01:02:03'::macaddr
        END,
    CASE (i % 3)
        WHEN 0 THEN '08:00:2b:01:02:03:04:05'::macaddr8
        WHEN 1 THEN NULL
        ELSE 'f4:ce:46:01:02:03:04:05'::macaddr8
        END,
    point(1920, 1080),
    box(point(0,0), point(1920, 1080)),
    polygon(box(point(0,0), point(1920, 1080))),
    path(polygon(box(point(0,0), point(1920, 1080)))),
    line(point(0,0), point(1920, 1080)),
    ('{"quality": "high", "autoplay": ' || (i % 2 = 0)::text || '}')::json,
    ('{"bitrate": ' || (1000 + (i * 100)) || ', "codec": "H264"}')::jsonb,
    xmlelement(name "metadata", xmlelement(name "id", i)),
    B'10101010',
    B'1010101011001100',
    ARRAY['English', 'Spanish', CASE i % 3 WHEN 0 THEN 'French' ELSE NULL END],
    ARRAY['English', 'Spanish', CASE i % 3 WHEN 0 THEN 'French' ELSE NULL END],
    ARRAY[95, 98, 99],
    ARRAY[10.5, 12.3, 15.7]::numeric(5,2)[],
    int4range(1, least(i * 10, 100)),
    int8range(1000, least(i * 1000, 10000)),
    tsrange('2024-01-01'::timestamp, ('2024-01-01'::timestamp + (i || ' days')::interval)),
    tstzrange('2024-01-01 UTC'::timestamptz, ('2024-01-01 UTC'::timestamptz + (i || ' days')::interval)),
    daterange('2024-01-01'::date, ('2024-01-01'::date + (i || ' days')::interval)::date),
    numrange(0.0, least(i * 10.0, 100.0)),
    (ARRAY['H264', 'H265', 'VP9', 'AV1', 'MPEG2', 'MPEG4'])[1 + (i % 6)]::video_codec,
    (ARRAY['MONO', 'STEREO', 'SURROUND_5_1', 'SURROUND_7_1', 'DOLBY_ATMOS'])[1 + (i % 5)]::audio_channel_config,
    ROW('BT.2020', 10, 'DCI-P3')::color_info,
    2024,
    to_tsvector('english', 'Media content item ' || i || ' description keywords'),
    to_tsquery('english', 'media & content')
FROM numbered_rows;

-- Insert rows 51-75
WITH numbered_rows AS (
    SELECT generate_series(51, 75) AS i
)
INSERT INTO public.media_technical_metadata (
    content_id,
    file_size_bytes,
    video_bitrate,
    audio_bitrate,
    average_framerate,
    actual_framerate,
    quality_score,
    peak_bitrate,
    monetary_cost,
    title,
    description,
    content_hash,
    created_timestamp,
    created_timestamp_tz,
    last_modified_date,
    duration,
    preferred_viewing_time,
    preferred_viewing_time_tz,
    thumbnail_image,
    is_drm_protected,
    cdn_primary_ip,
    cdn_subnet,
    mac_address,
    mac_address_8,
    video_dimensions,
    safe_area_box,
    crop_polygon,
    camera_path,
    subtitle_positions,
    player_config,
    stream_settings,
    metadata_xml,
    feature_flags,
    extended_flags,
    audio_languages,
    subtitle_languages,
    quality_scores,
    segment_durations,
    buffered_ranges,
    saturation_range,
    temporal_range,
    temporal_range_tz,
    date_availability,
    numeric_range,
    video_codec,
    audio_channels,
    color_information,
    release_year,
    search_document,
    search_query
)
SELECT
    gen_random_uuid(),
    -- Smaller file sizes
    CASE (i % 4)
        WHEN 0 THEN i * 1000000  -- 1MB increments
        WHEN 1 THEN 1000000     -- 1MB fixed
        WHEN 2 THEN NULL
        ELSE 100000000         -- 100MB max
        END,
    -- More reasonable video bitrates
    CASE (i % 3)
        WHEN 0 THEN 5000 + (i * 100)  -- 5-10Mbps range
        WHEN 1 THEN 15000             -- 15Mbps fixed
        ELSE 8000                      -- 8Mbps fixed
        END,
    -- Standard audio bitrates
    CASE (i % 3)
        WHEN 0 THEN 128
        WHEN 1 THEN 256
        ELSE 384
        END,
    -- Standard framerates
    CASE (i % 4)
        WHEN 0 THEN 23.976
        WHEN 1 THEN 29.97
        WHEN 2 THEN 59.94
        ELSE NULL
        END,
    -- Actual framerates (slightly off from nominal)
    CASE (i % 4)
        WHEN 0 THEN 23.976
        WHEN 1 THEN 29.970
        WHEN 2 THEN 59.940
        ELSE NULL
        END,
    -- Quality scores
    CASE (i % 5)
        WHEN 0 THEN 98.76
        WHEN 1 THEN 88.32
        WHEN 2 THEN 99.99
        WHEN 3 THEN NULL
        ELSE 50.00
        END,
    -- Peak bitrate
    CASE (i % 3)
        WHEN 0 THEN 15000
        WHEN 1 THEN 25000
        ELSE NULL
        END,
    -- Money values
    CASE (i % 4)
        WHEN 0 THEN '$0.00'::money
        WHEN 1 THEN '$99.99'::money
        WHEN 2 THEN '$999.99'::money
        ELSE NULL
        END,
    'Media Title ' || i,
    'Description for item ' || i || ' - High definition video',
    rpad(md5(i::text), 64, '0'),
    '2024-01-01'::timestamp + (i || ' days')::interval,
    '2024-01-01 UTC'::timestamptz + (i || ' days')::interval,
    '2024-01-01'::date + (i || ' days')::interval,
    make_interval(hours := (i % 4) + 1),  -- 1 to 4 hours duration
    '12:00:00'::time + ((i % 60) || ' minutes')::interval,
    '12:00:00 UTC'::timetz + ((i % 60) || ' minutes')::interval,
    generate_random_bytea(100),
    i % 2 = 0,
    CASE (i % 3)
        WHEN 0 THEN ('192.168.1.' || (i % 255))::inet
        WHEN 1 THEN NULL
        ELSE '10.0.0.1'::inet
        END,
    CASE (i % 3)
        WHEN 0 THEN '192.168.0.0/24'::cidr
        WHEN 1 THEN NULL
        ELSE '10.0.0.0/8'::cidr
        END,
    CASE (i % 3)
        WHEN 0 THEN '08:00:2b:01:02:03'::macaddr
        WHEN 1 THEN NULL
        ELSE 'f4:ce:46:01:02:03'::macaddr
        END,
    CASE (i % 3)
        WHEN 0 THEN '08:00:2b:01:02:03:04:05'::macaddr8
        WHEN 1 THEN NULL
        ELSE 'f4:ce:46:01:02:03:04:05'::macaddr8
        END,
    point(1920, 1080),
    box(point(0,0), point(1920, 1080)),
    polygon(box(point(0,0), point(1920, 1080))),
    path(polygon(box(point(0,0), point(1920, 1080)))),
    line(point(0,0), point(1920, 1080)),
    ('{"quality": "high", "autoplay": ' || (i % 2 = 0)::text || '}')::json,
    ('{"bitrate": ' || (1000 + (i * 100)) || ', "codec": "H264"}')::jsonb,
    xmlelement(name "metadata", xmlelement(name "id", i)),
    B'10101010',
    B'1010101011001100',
    ARRAY['English', 'Spanish', CASE i % 3 WHEN 0 THEN 'French' ELSE NULL END],
    ARRAY['English', 'Spanish', CASE i % 3 WHEN 0 THEN 'French' ELSE NULL END],
    ARRAY[95, 98, 99],
    ARRAY[10.5, 12.3, 15.7]::numeric(5,2)[],
    int4range(1, least(i * 10, 100)),
    int8range(1000, least(i * 1000, 10000)),
    tsrange('2024-01-01'::timestamp, ('2024-01-01'::timestamp + (i || ' days')::interval)),
    tstzrange('2024-01-01 UTC'::timestamptz, ('2024-01-01 UTC'::timestamptz + (i || ' days')::interval)),
    daterange('2024-01-01'::date, ('2024-01-01'::date + (i || ' days')::interval)::date),
    numrange(0.0, least(i * 10.0, 100.0)),
    (ARRAY['H264', 'H265', 'VP9', 'AV1', 'MPEG2', 'MPEG4'])[1 + (i % 6)]::video_codec,
    (ARRAY['MONO', 'STEREO', 'SURROUND_5_1', 'SURROUND_7_1', 'DOLBY_ATMOS'])[1 + (i % 5)]::audio_channel_config,
    ROW('BT.2020', 10, 'DCI-P3')::color_info,
    2024,
    to_tsvector('english', 'Media content item ' || i || ' description keywords'),
    to_tsquery('english', 'media & content')
FROM numbered_rows;

-- Insert rows 76-100
WITH numbered_rows AS (
    SELECT generate_series(76, 100) AS i
)
INSERT INTO public.media_technical_metadata (
    content_id,
    file_size_bytes,
    video_bitrate,
    audio_bitrate,
    average_framerate,
    actual_framerate,
    quality_score,
    peak_bitrate,
    monetary_cost,
    title,
    description,
    content_hash,
    created_timestamp,
    created_timestamp_tz,
    last_modified_date,
    duration,
    preferred_viewing_time,
    preferred_viewing_time_tz,
    thumbnail_image,
    is_drm_protected,
    cdn_primary_ip,
    cdn_subnet,
    mac_address,
    mac_address_8,
    video_dimensions,
    safe_area_box,
    crop_polygon,
    camera_path,
    subtitle_positions,
    player_config,
    stream_settings,
    metadata_xml,
    feature_flags,
    extended_flags,
    audio_languages,
    subtitle_languages,
    quality_scores,
    segment_durations,
    buffered_ranges,
    saturation_range,
    temporal_range,
    temporal_range_tz,
    date_availability,
    numeric_range,
    video_codec,
    audio_channels,
    color_information,
    release_year,
    search_document,
    search_query
)
SELECT
    gen_random_uuid(),
    -- Smaller file sizes
    CASE (i % 4)
        WHEN 0 THEN i * 1000000  -- 1MB increments
        WHEN 1 THEN 1000000     -- 1MB fixed
        WHEN 2 THEN NULL
        ELSE 100000000         -- 100MB max
        END,
    -- More reasonable video bitrates
    CASE (i % 3)
        WHEN 0 THEN 5000 + (i * 100)  -- 5-10Mbps range
        WHEN 1 THEN 15000             -- 15Mbps fixed
        ELSE 8000                      -- 8Mbps fixed
        END,
    -- Standard audio bitrates
    CASE (i % 3)
        WHEN 0 THEN 128
        WHEN 1 THEN 256
        ELSE 384
        END,
    -- Standard framerates
    CASE (i % 4)
        WHEN 0 THEN 23.976
        WHEN 1 THEN 29.97
        WHEN 2 THEN 59.94
        ELSE NULL
        END,
    -- Actual framerates (slightly off from nominal)
    CASE (i % 4)
        WHEN 0 THEN 23.976
        WHEN 1 THEN 29.970
        WHEN 2 THEN 59.940
        ELSE NULL
        END,
    -- Quality scores
    CASE (i % 5)
        WHEN 0 THEN 98.76
        WHEN 1 THEN 88.32
        WHEN 2 THEN 99.99
        WHEN 3 THEN NULL
        ELSE 50.00
        END,
    -- Peak bitrate
    CASE (i % 3)
        WHEN 0 THEN 15000
        WHEN 1 THEN 25000
        ELSE NULL
        END,
    -- Money values
    CASE (i % 4)
        WHEN 0 THEN '$0.00'::money
        WHEN 1 THEN '$99.99'::money
        WHEN 2 THEN '$999.99'::money
        ELSE NULL
        END,
    'Media Title ' || i,
    'Description for item ' || i || ' - Ultra HD video',
    rpad(md5(i::text), 64, '0'),
    '2024-01-01'::timestamp + (i || ' days')::interval,
    '2024-01-01 UTC'::timestamptz + (i || ' days')::interval,
    '2024-01-01'::date + (i || ' days')::interval,
    make_interval(hours := (i % 4) + 1),  -- 1 to 4 hours duration
    '12:00:00'::time + ((i % 60) || ' minutes')::interval,
    '12:00:00 UTC'::timetz + ((i % 60) || ' minutes')::interval,
    generate_random_bytea(100),
    i % 2 = 0,
    CASE (i % 3)
        WHEN 0 THEN ('192.168.1.' || (i % 255))::inet
        WHEN 1 THEN NULL
        ELSE '10.0.0.1'::inet
        END,
    CASE (i % 3)
        WHEN 0 THEN '192.168.0.0/24'::cidr
        WHEN 1 THEN NULL
        ELSE '10.0.0.0/8'::cidr
        END,
    CASE (i % 3)
        WHEN 0 THEN '08:00:2b:01:02:03'::macaddr
        WHEN 1 THEN NULL
        ELSE 'f4:ce:46:01:02:03'::macaddr
        END,
    CASE (i % 3)
        WHEN 0 THEN '08:00:2b:01:02:03:04:05'::macaddr8
        WHEN 1 THEN NULL
        ELSE 'f4:ce:46:01:02:03:04:05'::macaddr8
        END,
    point(3840, 2160),  -- 4K resolution for this batch
    box(point(0,0), point(3840, 2160)),
    polygon(box(point(0,0), point(3840, 2160))),
    path(polygon(box(point(0,0), point(3840, 2160)))),
    line(point(0,0), point(3840, 2160)),
    ('{"quality": "high", "autoplay": ' || (i % 2 = 0)::text || '}')::json,
    ('{"bitrate": ' || (1000 + (i * 100)) || ', "codec": "H264"}')::jsonb,
    xmlelement(name "metadata", xmlelement(name "id", i)),
    B'10101010',
    B'1010101011001100',
    ARRAY['English', 'Spanish', CASE i % 3 WHEN 0 THEN 'French' ELSE NULL END],
    ARRAY['English', 'Spanish', CASE i % 3 WHEN 0 THEN 'French' ELSE NULL END],
    ARRAY[95, 98, 99],
    ARRAY[10.5, 12.3, 15.7]::numeric(5,2)[],
    int4range(1, least(i * 10, 100)),
    int8range(1000, least(i * 1000, 10000)),
    tsrange('2024-01-01'::timestamp, ('2024-01-01'::timestamp + (i || ' days')::interval)),
    tstzrange('2024-01-01 UTC'::timestamptz, ('2024-01-01 UTC'::timestamptz + (i || ' days')::interval)),
    daterange('2024-01-01'::date, ('2024-01-01'::date + (i || ' days')::interval)::date),
    numrange(0.0, least(i * 10.0, 100.0)),
    (ARRAY['H264', 'H265', 'VP9', 'AV1', 'MPEG2', 'MPEG4'])[1 + (i % 6)]::video_codec,
    (ARRAY['MONO', 'STEREO', 'SURROUND_5_1', 'SURROUND_7_1', 'DOLBY_ATMOS'])[1 + (i % 5)]::audio_channel_config,
    ROW('BT.2020', 10, 'DCI-P3')::color_info,
    2024,
    to_tsvector('english', 'Media content item ' || i || ' description keywords'),
    to_tsquery('english', 'media & content')
FROM numbered_rows;

-- Clean up the temporary function after all inserts are complete
DROP FUNCTION IF EXISTS generate_random_bytea(integer);