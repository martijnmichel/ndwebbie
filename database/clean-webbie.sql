TRUNCATE planet_stats ;
TRUNCATE galaxies ;
TRUNCATE alliance_stats ;
TRUNCATE defense_requests;
TRUNCATE graphs;
TRUNCATE fleet_ships;
TRUNCATE incomings;
TRUNCATE raid_claims;
/*TRUNCATE dumps;*/
TRUNCATE scan_requests;
TRUNCATE fleet_scans;
TRUNCATE planet_scans;
TRUNCATE development_scans;
TRUNCATE irc_requests;
UPDATE users SET scan_points = 0, defense_points = 0, attack_points = 0, humor_points = 0, rank = NULL, planet = NULL;
DELETE FROM scans;
DELETE FROM raids;
DELETE FROM calls;
DELETE FROM fleets;
DELETE FROM covop_attacks;
DELETE FROM planets ;
DELETE FROM alliances WHERE id > 1;
SELECT * FROM alliances;
DELETE FROM forum_threads WHERE fbid = -2;
DELETE FROM forum_threads WHERE fbid = -3;
DELETE FROM forum_threads WHERE fbid = -5;
DELETE FROM forum_threads WHERE fbid = 12;
DELETE FROM forum_posts WHERE ftid IN (SELECT ftid FROM forum_threads WHERE fbid = -1);
ALTER SEQUENCE alliances_id_seq RESTART 2;
ALTER SEQUENCE calls_id_seq RESTART 1;
ALTER SEQUENCE defense_requests_id_seq RESTART 1;
ALTER SEQUENCE fleets_id_seq RESTART 1;
ALTER SEQUENCE incomings_id_seq RESTART 1;
ALTER SEQUENCE planets_id_seq RESTART 1;
ALTER SEQUENCE raid_targets_id_seq RESTART 1;
ALTER SEQUENCE raids_id_seq RESTART 1;
ALTER SEQUENCE scans_id_seq RESTART 1;
ALTER SEQUENCE irc_requests_id_seq RESTART 1;
ALTER SEQUENCE scan_requests_id_seq RESTART 1;
