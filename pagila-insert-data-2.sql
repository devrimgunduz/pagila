-- Insert 100 rows of sample data
INSERT INTO public.streaming_activity
(film_id, customer_id, view_count, stream_start_time, watch_duration, playback_position, player_settings)
VALUES
-- First 5 rows shown in detail for reference
(1, 1, 12345678, '14:30:00', '2 hours 15 minutes', 1234.56, '{"quality": "HD", "subtitles": true, "volume": 0.8, "playback_speed": 1.0}'::jsonb),
(2, 2, 8765432, '20:15:00', '1 hour 45 minutes', 987.65, '{"quality": "4K", "subtitles": false, "volume": 0.7, "playback_speed": 1.25}'::jsonb),
(3, 3, 2345678, '18:20:00', '1 hour 30 minutes', 2468.10, '{"quality": "SD", "subtitles": true, "volume": 0.9, "playback_speed": 1.0}'::jsonb),
(4, 4, 9876543, '12:00:00', '2 hours 30 minutes', 3579.24, '{"quality": "HD", "subtitles": false, "volume": 0.6, "playback_speed": 1.5}'::jsonb),
(5, 5, 3456789, '21:45:00', '1 hour 55 minutes', 1357.90, '{"quality": "4K", "subtitles": true, "volume": 0.85, "playback_speed": 1.0}'::jsonb),

-- Generating 95 more rows with varying data
SELECT
    (random() * 1000)::integer AS film_id,
    (random() * 500)::integer AS customer_id,
    (random() * 10000000)::bigint AS view_count,
    (
        format('%s:%s:00',
               LPAD((random() * 23)::text, 2, '0'),
               LPAD((random() * 59)::text, 2, '0')
        )
        )::time AS stream_start_time,
    (format('%s hours %s minutes',
            (random() * 3 + 1)::integer,
            (random() * 59)::integer
     ))::interval AS watch_duration,
    (random() * 5000)::double precision AS playback_position,
    jsonb_build_object(
            'quality', (ARRAY['SD', 'HD', '4K'])[floor(random() * 3 + 1)],
            'subtitles', random() > 0.5,
            'volume', round((random() * 0.5 + 0.5)::numeric, 2),
            'playback_speed', round((ARRAY[0.75, 1.0, 1.25, 1.5])[floor(random() * 4 + 1)]::numeric, 2)
    ) AS player_settings
FROM generate_series(6, 100);