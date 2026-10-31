# The jobs page (/jobs) is behind basic auth with MISSION_CONTROL_USER and MISSION_CONTROL_PASSWORD. Without both, it
# answers 401 to everyone.
MissionControl::Jobs.http_basic_auth_user = ENV["MISSION_CONTROL_USER"].presence
MissionControl::Jobs.http_basic_auth_password = ENV["MISSION_CONTROL_PASSWORD"].presence
