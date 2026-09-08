# 04 - Agent API Routes

The agent exposes a REST-like internal API over Unix domain sockets. All messages use `{verb, path, msgId, payload}` JSON format.

Routes marked `(sub)` are subscription endpoints — the agent pushes EVENT messages when data changes.

---

## Meta

```
GET  /routes                              # Lists ALL available routes (self-documenting!)
GET  /configuration
GET  /permissions
GET  /logioptions/info
SET  /logioptions/launch/frontend
SET  /firmwareupdate/launch/frontend
GET  /beta_testing/features
GET  /lifecycle/backend_started           (sub)
GET  /lifecycle/backend_shutdown          (sub)
GET  /lifecycle/logivoice_shutdown        (sub)
```

## System

```
GET  /system/info
GET  /system/settings
SET  /system/hotkey/register
SET  /system/hotkey/unregister
SET  /system/hotkey/pause
SET  /system/hotkey/resume
GET  /system/hotkey/registered            (sub)
GET  /system/hotkey/unregistered          (sub)
GET  /system/hotkey/triggered             (sub)
GET  /system/hotkey/paused                (sub)
GET  /system/hotkey/resumed               (sub)
GET  /system/hotkey/registration/allowed
GET  /system/hotkey/registration/allowed/status  (sub)
GET  /secure_input_enabled
GET  /get_secure_input_app_name
SET  /set_feature_flag
```

## Devices

```
GET  /devices/list
GET  /devices/map
GET  /devices/model/info
GET  /devices/support/info
GET  /devices/driver_info
GET  /devices/resources
GET  /devices/resources/default_gestures
GET  /devices/resources/default_slots
GET  /devices/resources/dynamic_slots
GET  /devices/resources/rac_slots
GET  /devices/ever_connected/list
SET  /devices/ever_connected/clear
GET  /devices/easy_switch
SET  /devices/change_owner
SET  /devices/fn_inversion/notify
SET  /devices/special_keys_divert_state/configure
GET  /devices/bt_report
GET  /devices/wheel_mode_shift

# Subscriptions (global)
GET  /devices/state/changed               (sub)
GET  /devices/state/activated             (sub)
GET  /devices/state/deactivated           (sub)
GET  /devices/state/easy_switch_cache_updated  (sub)
GET  /devices/host_changed                (sub)
GET  /devices/preferences/changed         (sub)
GET  /devices/unknown/connected           (sub)
GET  /devices/quarantine_notification     (sub)

# DevIO events
GET  /devices/devio/device_arrival        (sub)
GET  /devices/devio/device_connect        (sub)
GET  /devices/devio/device_disconnect     (sub)
GET  /devices/devio/device_removal        (sub)
GET  /devices/devio/raw/device_arrival    (sub)
GET  /devices/devio/raw/device_removal    (sub)
GET  /devices/options/device_arrival      (sub)
GET  /devices/options/device_removal      (sub)
```

## Per-Device (`%s` = device_id)

```
GET  /devices/%s/info
GET  /devices/%s/interface/list
GET  /devices/%s/list
GET  /devices/%s/slots
GET  /devices/%s/hidden_slots
GET  /devices/%s/masked_zones
GET  /devices/%s/resource
GET  /devices/%s/persistent_data
GET  /devices/%s/blockers
SET  /devices/%s/defaults
SET  /devices/%s/blocker/resolve
GET  /devices/%s/easy_switch
SET  /devices/%s/easy_switch/change
SET  /devices/%s/change_channel
SET  /devices/%s/change_owner
GET  /devices/%s/fn_inversion
GET  /devices/%s/fn_inversion_2
GET  /devices/%s/keep_alive
SET  /devices/%s/terminate_keep_alive
GET  /devices/%s/special_keys_divert_state
GET  /devices/%s/brightness
GET  /devices/%s/brightness_changed       (sub)
GET  /devices/%s/pedal_settings
GET  /devices/%s/wheel_settings
GET  /devices/%s/touchpad_settings/configure
GET  /devices/%s/touchpad/gesture_report
GET  /devices/%s/touchpad/gesture_reporting
```

## Pairing

```
SET  /devices/%s/pair
SET  /devices/%s/pair/cancel
SET  /devices/%s/unpair
GET  /devices/%s/pair/changed             (sub)
GET  /devices/%s/pair/passkey/displayed   (sub)
GET  /devices/%s/pair/passkey/entry       (sub)
GET  /devices/%s/discovery/advertised     (sub)
GET  /devices/%s/discovery/changed        (sub)
GET  /devices/%s/discovery/recovery       (sub)
GET  /devices/%s/discovery/status
GET  /devices/%s/locking/changed          (sub)
GET  /devices/%s/locking/status
GET  /receivers/%s/unpair
```

## Battery

```
GET  /battery/%s/state
GET  /battery/%s/state/changed            (sub)
GET  /battery/%s/state_override
GET  /battery/%s/warning                  (sub)
GET  /battery/%s/sleep_timer
GET  /battery/%s/lighting
GET  /battery/%s/power_consumption/changed (sub)
GET  /battery/state/changed               (sub)
GET  /battery/warning                     (sub)
GET  /low_battery/notify                  (sub)
GET  /low_battery/rule
GET  /low_light/notify                    (sub)
```

## Mouse Settings

```
SET  /mouse_settings/configure
SET  /mouse_scroll_wheel_settings/configure
SET  /mouse_thumb_wheel_settings/configure
SET  /mouse_precision_mode/configure
GET  /mouse/%s/info
GET  /mouse/%s/dpi_always_on
GET  /mouse/%s/dpi_shift
GET  /mouse/%s/dpi_lighting_refresh
GET  /mouse/%s/hybrid_engine
GET  /mouse/%s/pointer_speed
GET  /mouse/%s/precision_mode
GET  /mouse/%s/mode_status
GET  /mouse/%s/angle_snapping
GET  /mouse/global/swap
SET  /mouse/global/swap
GET  /mouse/swap
SET  /mouse/swap
GET  /scrollwheel/%s/params
GET  /scrollwheel/%s/ratchet_change       (sub)
GET  /smartshift/%s/params
GET  /thumbwheel/%s/params
GET  /virtual_thumbwheel/%s/params
GET  /surface_tuning/%s/active
GET  /surface_tuning/%s/surface
GET  /surface_tuning/%s/surfaces
SET  /surface_tuning/%s/start
SET  /surface_tuning/%s/save
SET  /surface_tuning/%s/abort
GET  /surface_tuning/%s/event             (sub)
```

## Keyboard Settings

```
SET  /keyboard_settings/configure
GET  /keyboard/%s/keyboard_oslayout
GET  /keyboard/lock_key_pressed           (sub)
SET  /fn_inversion_settings/configure
SET  /disable_keys_settings/configure
SET  /disable_keys_capabilities/configure
GET  /disable_keys/%s/capabilities
GET  /disable_keys/%s/state
```

## Backlight

```
SET  /backlight_settings/configure
GET  /backlight/%s/backlight_level
GET  /backlight/%s/backlight_level_changed (sub)
GET  /backlight/%s/backlight_duration
GET  /backlight/%s/backlight_duration_changed (sub)
GET  /backlight/%s/backlight_effect
GET  /backlight/%s/backlight_effect_changed (sub)
GET  /backlight/%s/backlight_1983_settings_for
GET  /backlight/%s/state
GET  /backlight/%s/state_changed          (sub)
GET  /backlight/%s/info_changed           (sub)
GET  /backlight/%s/power_save
GET  /backlight/%s/power_save_changed     (sub)
GET  /backlight/info_changed              (sub)
SET  /brightness_settings/configure
```

## Crown / Dial

```
GET  /crown/%s/mode
GET  /crown/%s/mode_change                (sub)
SET  /craft_crown_settings/configure
```

## Profiles (V2)

```
GET  /v2/profile
GET  /v2/profile/active
GET  /v2/profile/active/changed           (sub)
GET  /v2/profiles
GET  /v2/profiles/slice
GET  /v2/profiles/slice_all
GET  /v2/profiles/slice_v2
GET  /v2/profiles/slice/preview
GET  /v2/profiles/slice_v2/preview
GET  /v2/profiles/update                  (sub)
SET  /v2/profiles/copy_settings
GET  /v2/profiles/merge
SET  /v2/profiles/device/assignment_sync
GET  /v2/profiles/device/assignment_sync_complete (sub)
GET  /v2/profiles/enabled_integration_guids
GET  /v2/profiles/integrations_are_required
GET  /v2/profiles/integrations_restored   (sub)
GET  /v2/profiles/is_device_default
GET  /v2/profiles/macro_assignment_refs
GET  /v2/profiles/action_event_triggered  (sub)
GET  /v2/profiles/software_events/slot_ids/report (sub)
```

## Assignments

```
GET  /v2/assignment
SET  /v2/assignment
SET  /v2/assignment_no_notification
SET  /v2/assignment/multiple
GET  /v2/defaults/slice
GET  /v2/defaults/slice_v2
GET  /v2/defaults/slots
SET  /v2/migration/initiate
SET  /v2/migration/migrate
GET  /v2/trigger/event                    (sub)
GET  /v2/trigger/event/executed           (sub)
```

## RAP (Remote Assignable Properties)

```
GET  /rac/supported_cards
GET  /rap_v2/supported_cards
GET  /rap_v2/rac_current
GET  /rap_v2/rac_arrived                  (sub)
GET  /rap_v2/rac_announce_current
GET  /rap_v2/available_app
GET  /rap_v2/app_id_name_map
GET  /rap_v2/card_by_app
GET  /rap_v2/preset
GET  /rap_v2/presets
GET  /rap_v2/macros/presets
SET  /rap_v2/rename_cards
```

## Macros

```
GET  /macros/status
GET  /macros/predefined
GET  /macros/presets
GET  /macros/validate
SET  /macros/export
SET  /macros/import
SET  /macros/playback/execute
SET  /macros/playback/sequence/execute
SET  /macros/gesture/execute
SET  /macros/gesture_2way/execute
SET  /macros/gesture_4way/execute
SET  /macros/gesture_crown/execute
SET  /macros/gesture/stop_tap_scroll_inertia
SET  /macro/execute/stop
GET  /macro/executed                      (sub)
GET  /macros/sequence/status              (sub)
GET  /macros/device/predefined_ids
SET  /macros/fill_device_alert_card
SET  /macros/quick_recording_action
GET  /macros/onboarding/completed
GET  /macros/onboarding/ready             (sub)
GET  /macros/integrations_are_required
GET  /macros/ai_prompt_builder/enabled
SET  /macros/ai_prompt_builder/enabled
GET  /macros/ai_prompt_builder/enabled/device_connect (sub)
GET  /macros/ai_prompt_builder/logging_changed (sub)
GET  /macros/ai_prompt_builder/updated    (sub)
GET  /macros/ai_onboarding/completed
GET  /macros/custom_categories/storage
SET  /macros/custom_categories/storage/append
SET  /macros/custom_categories/storage/update
SET  /macros/custom_categories/restore
```

## Macro Assignments

```
GET  /macro_assignment
GET  /macro_assignment/active
SET  /macro_assignment/create
GET  /macro_assignment/predefined
SET  /macro_assignment/remove
SET  /macro_assignment/update
GET  /macro_assignments/all
SET  /macro_assignments/create
GET  /macro_assignments/ids
SET  /macro_assignments/update
GET  /macro_infos/all
GET  /macro_infos/cleaned/all
GET  /macro_infos/ids/all
SET  /macro_infos/mutate
SET  /macro_infos/restore
SET  /macro_infos/update
SET  /macro_refs/update
SET  /macro_assignment/custom_categories
```

## Applications

```
GET  /applications
GET  /applications/all
GET  /applications/installed
GET  /applications/running
SET  /applications/scan
GET  /applications/scan/installed         (sub)
GET  /applications/predefined
GET  /applications/predefined/installed
GET  /applications/logi/installed
GET  /applications/focus/last
GET  /application
GET  /application/focus
SET  /application/disable
GET  /application/installed
GET  /application/additional_data
GET  /application/command/colors
GET  /application/require/restart/paths
GET  /applications/event                  (sub)
GET  /applications/event/raw              (sub)
SET  /applications/event/register
GET  /applications/event/registered       (sub)
GET  /applications/event/triggered        (sub)
SET  /applications/event/unregister
GET  /applications/event/unregistered     (sub)
```

## DFU (Firmware Update)

```
GET  /dfu/%s/info
SET  /dfu/%s/check
SET  /dfu/%s/download
SET  /dfu/%s/start
SET  /dfu/%s/cancel
SET  /dfu/%s/reset
SET  /dfu/%s/reboot_device
GET  /dfu/%s/update_progress              (sub)
GET  /dfu/%s/update_result                (sub)
GET  /dfu/%s/all_events
SET  /dfu/config/download
SET  /dfu/config/update
GET  /dfu/update_result                   (sub)
GET  /dfu/update/available                (sub)
```

## Updates (App Updates)

```
GET  /updates/info
SET  /updates/check_now
SET  /updates/download
SET  /updates/install
SET  /updates/reboot
GET  /updates/status
GET  /updates/channel
SET  /updates/enable
GET  /updates/depots
GET  /updates/depot/info
GET  /updates/depot/content
GET  /updates/depot/content_multiple
SET  /updates/depot/reinstall
GET  /updates/depot/reinstall/result      (sub)
GET  /updates/next/depots
GET  /updates/next/depot/info
GET  /updates/next/info
GET  /updates/host_address
GET  /updates/reboot_needed               (sub)
GET  /updates/restart_incoming            (sub)
GET  /updates/frontend_restart_incoming   (sub)
SET  /updates/restart_now
GET  /updates/auto_update_needed          (sub)
SET  /updates/periodic_check
GET  /updates/device_ownership
SET  /updates/purge
SET  /updates/reset
SET  /updates/repair_configuration
SET  /updates/run_launchable
GET  /updates/pipeline
GET  /updates/pipeline/info
GET  /updates/remote
GET  /updates/remote/execution_status
GET  /updates/plugin_installer_status
GET  /updates/plugin_installer_status_changed (sub)
GET  /updates/updater_service/info
SET  /updates/updater_service/install
```

## Haptics

```
SET  /haptic_settings/configure
GET  /haptics/%s/config
GET  /haptics/%s/event_sources
GET  /haptics/%s/properties
GET  /haptics/%s/status
GET  /haptics/%s/status_changed           (sub)
SET  /haptics/%s/play_waveform
GET  /haptics/%s/get_playing_waveform
SET  /haptics/%s/stop_waveform
SET  /haptics/%s/start_breathing_exercise
SET  /haptics/%s/stop_breathing_exercise
GET  /haptics/event                       (sub)
GET  /haptics/waveform/event              (sub)
GET  /haptics/trigger_haptic_waveform_info
SET  /haptics/trigger_waveform_execute
```

## Flow (Cross-Computer)

```
GET  /flow/%s/config
GET  /flow/%s/config_changed              (sub)
GET  /flow/%s/device_location
GET  /flow/%s/device_location_changed     (sub)
GET  /flow/%s/device_peer_status
GET  /flow/%s/device_peer_status_changed  (sub)
SET  /flow/%s/discover
GET  /flow/%s/discover_progress           (sub)
SET  /flow/%s/reset
```

## Hosts Info / Easy Switch

```
GET  /hosts_info/%s/current
GET  /hosts_info/%s/hosts_names
GET  /hosts_info/%s/ble
GET  /hosts_info/%s/keyboardlayout
SET  /hosts_info/%s/remove
SET  /change_host/%s/host
GET  /coupled_easy_switch/%s/compatible_devices
SET  /coupled_easy_switch/%s/coupled_switch_link_device
GET  /coupled_easy_switch/%s/follow_change_host
GET  /coupled_easy_switch/%s/follow_cookies
SET  /coupled_easy_switch/add_pending_device
```

## Notifications

```
GET  /notifications
GET  /notifications_settings
SET  /notifications/post
GET  /notifications/backlight_changed     (sub)
GET  /notifications/battery_status        (sub)
GET  /notifications/caps_lock             (sub)
GET  /notifications/fn_inversion          (sub)
GET  /notifications/fn_lock               (sub)
GET  /notifications/mic                   (sub)
GET  /notifications/num_lock              (sub)
GET  /notifications/scroll_lock           (sub)
GET  /notifications/toast/event           (sub)
```

## macOS Security

```
GET  /macos_security/accessibility
GET  /macos_security/accessibility/event  (sub)
GET  /macos_security/bluetooth
GET  /macos_security/bluetooth/event      (sub)
GET  /macos_security/input_monitoring
GET  /macos_security/screen_recording
GET  /macos_security/screen_recording/event (sub)
```

## Audio

```
GET  /audio/%s/volume
SET  /audio/%s/volume
GET  /audio/%s/mute
SET  /audio/%s/mute
GET  /audio/%s/mute_notification
SET  /audio/%s/mic_mute_toggle
GET  /audio/%s/sidetone
SET  /audio/%s/sidetone
GET  /audio/%s/onboard
SET  /audio/%s/onboard
SET  /audio/%s/fix_hypersonic_mic_defaults
GET  /audio/%s/hardware_noise_reduction
SET  /audio/%s/hardware_noise_reduction
GET  /audio/%s/volume_notifications       (sub)
GET  /microphone/%s/mode
GET  /microphone/%s/mute
GET  /microphone/%s/polar_pattern
GET  /microphone/%s/volume
GET  /microphone/mode/changed             (sub)
GET  /microphone/polar_pattern/changed    (sub)
```

## Gestures / Touchpad

```
SET  /gesture/%s/configure
SET  /gesture/configure
GET  /gestures/%s/interval_before_inertia_stop
GET  /gestures/%s/output                  (sub)
SET  /touchpad_gesture/%s/configure
SET  /touchpad_gesture/configure
SET  /touchpad_settings/configure
GET  /touchpad/gesture_reporting
SET  /touchpad/open/settings
```

## Input

```
GET  /input/%s/mstate
GET  /input/button_map
GET  /input/event                         (sub)
GET  /input/mr                            (sub)
GET  /input/mstate/changed                (sub)
GET  /inputxy_event                       (sub)
SET  /siminput
SET  /siminput/release
SET  /siminput/scroll/inertia
SET  /siminput/scroll/inertia/stop
```

## Input Tracker

```
GET  /input_tracker/events                (sub)
SET  /input_tracker/start
SET  /input_tracker/stop
GET  /input_tracker/options
GET  /input_tracker/caps_lock_pressed     (sub)
GET  /input_tracker/fn_lock_pressed       (sub)
GET  /input_tracker/num_lock_pressed      (sub)
GET  /input_tracker/scroll_lock_pressed   (sub)
GET  /input_tracker/initiator_alive       (sub)
```

## Presenter / Highlights

```
GET  /logipresentation/logi_presentation_status
SET  /logipresentation/logi_presentation_start_presentation
GET  /logipresentation/logi_presentation_report
GET  /logipresentation/logi_presentation_screen_rect
SET  /logihighlights/logi_highlights_start_feature
SET  /logihighlights/logi_highlights_stop_feature
SET  /logihighlights/logi_highlights_change_highlight
SET  /logihighlights/logi_highlights_center_highlight_now
SET  /logihighlights/logi_highlights_set_cursor_pos
GET  /logihighlights/logi_highlights_settings
SET  /logihighlights/logi_highlights_start_focus_screen
SET  /logihighlights/logi_highlights_stop_focus_screen
SET  /presentation_timers/configure
GET  /presentation_timers/timer_settings
GET  /presentation_timers/timer_status
GET  /presentation_timers/vibration_start (sub)
SET  /presenter_settings/configure
GET  /presenter/%s/presenter_settings
SET  /presenter/%s/vibrate
GET  /presenter/presenter_settings_changed (sub)
SET  /presenter/vibrate
```

## Lighting / Illumination

```
GET  /lighting/%s/state
GET  /lighting/%s/mode
SET  /lighting/%s/mode/wake
GET  /lighting/%s/brightness
GET  /lighting/%s/power_saving
GET  /lighting/%s/low_battery
SET  /lighting/%s/low_battery/dismiss
GET  /lighting/%s/firmware/effects
GET  /lighting/%s/firmware/brightness
SET  /lighting/%s/firmware/cycle_brightness
GET  /lighting/%s/firmware/bootup
GET  /lighting/%s/firmware/indicator
GET  /lighting/%s/firmware/battery/warning
GET  /lighting/%s/custom/effects
SET  /lighting/%s/custom/effect/save
SET  /illumination_light_settings/configure
GET  /illumination_light/%s/color_range
GET  /illumination_light/%s/color_range_changed (sub)
GET  /illumination_light/%s/light_settings
GET  /illumination_light/%s/selected_camera_id
GET  /illumination_light/light_settings_changed (sub)
```

## Webcam / UVC

```
SET  /webcam_camera_settings/configure
SET  /webcam_crop_settings/configure
SET  /webcam_focus_settings/configure
SET  /webcam_global_settings/configure
SET  /webcam_microphone_settings/configure
SET  /webcam_video_settings/configure
SET  /webcam_settings/sync
GET  /webcam_in_use
GET  /webcams/in_configuration_devices
GET  /webcams/in_configuration_devices_changed (sub)
GET  /uvc/%s/camera/settings
GET  /uvc/%s/capabilities
GET  /uvc/%s/crop/get_settings
SET  /uvc/%s/crop/settings
SET  /uvc/%s/factory_reset
GET  /uvc/%s/focus/settings
SET  /uvc/%s/focus/settings
GET  /uvc/%s/global/settings
SET  /uvc/%s/global/settings
SET  /uvc/%s/microphone/enable
GET  /uvc/%s/microphone/settings
SET  /uvc/%s/microphone/settings
GET  /uvc/%s/orientation
GET  /uvc/%s/preview_resolutions
GET  /uvc/%s/rightsight
GET  /uvc/%s/rightsight_working_status
GET  /uvc/%s/rightsight/hidreport
SET  /uvc/%s/rightsight/hidreport
GET  /uvc/%s/showmode/hidreport
SET  /uvc/%s/showmode/hidreport
GET  /uvc/%s/showmode/settings
SET  /uvc/%s/showmode/settings
GET  /uvc/%s/stream_started              (sub)
GET  /uvc/%s/streaming_status
GET  /uvc/%s/video/settings
SET  /uvc/%s/video/settings
GET  /uvc/showmode/notification          (sub)
```

## Integrations / Plugins

```
GET  /api/v1/integration
GET  /api/v1/integrations
GET  /api/v1/integrations/active
GET  /api/v1/integrations/active/all
GET  /api/v1/integrations/active/instances
GET  /api/v1/integrations/active/top
GET  /api/v1/integrations/states
SET  /api/v1/integration/activate
SET  /api/v1/integration/deactivate
SET  /api/v1/integration/download
SET  /api/v1/integration/enable
SET  /api/v1/integration/launch_type
SET  /api/v1/integration/register
GET  /api/v1/integration/obs/status
GET  /api/v1/integration/plugin/installer/status
SET  /api/v1/integration/plugin/installer/status/set
SET  /api/v1/integration/sdk/action
SET  /api/v1/integration/sdk/action/invoke
SET  /api/v1/integration/sdk/%s/action/invoke
SET  /api/v1/actions/invoke
SET  /api/v1/actions/register
SET  /api/v1/events/broadcast
GET  /api/v1/events/schemes
SET  /api/v1/events/update
GET  /api/v1/wheel_settings
SET  /integration/install
SET  /integration/install_multiple
GET  /integration/is_installed
GET  /integration/are_installed
GET  /integration/plugin/photoshop/uxp_plugin_exists
SET  /integration_manager/settings/led_sdk_enabled
```

## LPS (Loupedeck Plugin Service)

```
GET  /lps/status
GET  /lps/plugins
GET  /lps/properties
SET  /lps/stop
GET  /lps/service_state
GET  /lps/service_stopping                (sub)
GET  /lps/endpoint/info
GET  /lps/endpoint/info_changed           (sub)
SET  /lps/endpoint/control_plugin_service
SET  /lps/start_device
SET  /lps/show_device
SET  /lps/dismiss_device
SET  /lps/assign
SET  /lps/input
GET  /lps/overlay_settings
SET  /lps/overlay_settings
GET  /lps/overlay_settings_changed        (sub)
SET  /lps/show_overlay
SET  /lps/hide_overlay
SET  /lps/show_console_ui
SET  /lps/set_image_size
SET  /lps/request_device_redraw
GET  /lps/action/list
SET  /lps/action/register
SET  /lps/action/unregister
SET  /lps/action/execute
SET  /lps/action/execute_registered
GET  /lps/action_description
GET  /lps/plugin_actions
GET  /lps/plugin_actions_changed          (sub)
GET  /lps/plugin_action_symbols
GET  /lps/plugin_status_changed           (sub)
GET  /lps/plugin_loaded                   (sub)
GET  /lps/plugin_unloaded                 (sub)
GET  /lps/plugin_preference_changed       (sub)
GET  /lps/plugin_installation_started_event (sub)
GET  /lps/plugin_installation_progress    (sub)
GET  /lps/plugin_installation_finished    (sub)
SET  /lps/install_lps
SET  /lps/install_plugin_from_file
SET  /lps/install_plugin_from_marketplace
SET  /lps/install_plugins_from_marketplace
SET  /lps/uninstall_plugin
SET  /lps/start_library_package_update_check
GET  /lps/library_package_update_available (sub)
GET  /lps/depot_present
GET  /lps/feature_flag/enabled
SET  /lps/process_url
GET  /lps/url_processing_finished         (sub)
SET  /lps/login_user
SET  /lps/logout_user
GET  /lps/login_info
GET  /lps/login_info_required             (sub)
GET  /lps/login_required                  (sub)
GET  /lps/logout_required                 (sub)
GET  /lps/user_login_status_changed       (sub)
GET  /lps/lps_is_not_running              (sub)
SET  /lps/notify_plugin_service_disabled
GET  /lps/page_changed                    (sub)
GET  /lps/adjustment_value_changed        (sub)
GET  /lps/control_assignment_changed      (sub)
SET  /lps/enable_notification
SET  /lps/enabled_in_background
GET  /lps/context_active                  (sub)
GET  /lps/context_inactive                (sub)
GET  /lps/event/button                    (sub)
GET  /lps/event/encoder                   (sub)
GET  /lps/event/mouse                     (sub)
GET  /lps/plugin/event_raised             (sub)
GET  /lps/plugin/event_source_arrived     (sub)
GET  /lps/plugin/event_source_departed    (sub)
GET  /lps/plugin/event_source_modified    (sub)
GET  /lps/plugin/event_sources
GET  /lps/resources/depot_content
SET  /lps/resources/request_depot_content
GET  /lps/telemetry_status
GET  /lps/logging/status
SET  /lps/enable_trace_events
SET  /lps/clear_trace_events
GET  /lps/trace_events
SET  /lps/emulate/trigger_easy_switch
SET  /lps/update_connected_device_list
```

## Loupedeck (External API)

```
GET  /v1/devices/get
SET  /v1/action/execute
GET  /v1/actions/get
GET  /v1/user_info/get
GET  /v1/loupedeck/device_list
GET  /v1/loupedeck/action_list
SET  /v1/loupedeck/invoke
GET  /v1/loupedeck/changed                (sub)
GET  /v1/loupedeck/action_changed         (sub)
GET  /v1/loupedeck/trigger_event          (sub)
```

## Accounts / SSO

```
GET  /accounts/config
SET  /accounts/config
GET  /accounts/config/changed             (sub)
GET  /accounts/email_subscription
SET  /accounts/email_subscription
GET  /accounts/email_subscription/is_opted_in
GET  /accounts/is_authenticated
SET  /accounts/login_websso
SET  /accounts/logout_session
SET  /accounts/register_email
GET  /accounts/register_email_status
SET  /accounts/relay_pkce_code
SET  /accounts/request_email
GET  /accounts/user_info
SET  /accounts/user_info_edit
GET  /accounts/user_info_refreshed        (sub)
```

## LogiVoice (Dictation)

```
SET  /logivoice/start
SET  /logivoice/toggle_logi_voice
SET  /logivoice/toggle_logi_voice_mode
SET  /logivoice/launch_voice_search
GET  /logivoice/get_accessibility
GET  /logivoice/get_microphone_permission
GET  /logivoice/get_microphone_permission_with_system_alert
GET  /logivoice/get_current_recognition_mode
GET  /logivoice/get_long_speech_enabled
GET  /logivoice/get_smooth_mode_enabled
SET  /logivoice/set_dictation_language
SET  /logivoice/set_translation_language
SET  /logivoice/set_punctuation_mode
SET  /logivoice/set_vocabulary_type
SET  /logivoice/set_microphone
SET  /logivoice/set_long_speech_enabled
SET  /logivoice/set_smooth_mode_enabled
GET  /logivoice/supported_dictation_languages
GET  /logivoice/supported_translation_languages
GET  /logivoice/supported_punctuation_modes
GET  /logivoice/supported_vocabulary_types
GET  /logivoice/available_microphones
GET  /logivoice/voice_search_enabled
GET  /logivoice/voice_recognition_started (sub)
GET  /logivoice/voice_recognition_stopped (sub)
GET  /logivoice/accessibility/event       (sub)
GET  /logivoice/microphone_permission/event (sub)
GET  /logivoice/microphones_changed       (sub)
GET  /logivoice/logi_voice_mode_changed   (sub)
GET  /logivoice/logi_voice_settings_triggered (sub)
```

## Analytics / Telemetry

```
SET  /analytics/send_event
GET  /analytics/status
GET  /analytics/data
SET  /analytics/collect_host_info
GET  /scarif/config
GET  /scarif/info
GET  /scarif/settings
GET  /scarif/status
GET  /scarif/telemetry
GET  /scarif/event                        (sub)
GET  /scarif/event/broadcasted            (sub)
```

## Settings Backup

```
GET  /backups/device/list
SET  /backups/device/start_backup
SET  /backups/device/start_backup_all
SET  /backups/device/start_restore
SET  /backups/device/force_autobackup
SET  /backups/device/force_autobackup_all
SET  /backups/device/clean_all
GET  /backups/device/status_backup        (sub)
GET  /backups/device/status_restore       (sub)
SET  /backups/macros/clean_all
GET  /backups/macros/status_restore       (sub)
```

## Offers

```
GET  /offer/retrieve
SET  /offer/redeem
SET  /offer/revoke
GET  /offer/update_status                 (sub)
GET  /offer/perplexity/request
GET  /api/offer/available
GET  /api/offer/claimed
SET  /api/offer/redeem
GET  /api/offer/promocodes/perplexityai
```

## Logging / Debug

```
SET  /log/debug
GET  /logging/optionsplus_backend/status
SET  /logging/optionsplus_backend/trigger
GET  /logging/optionsplus_updater/path
SET  /logging/optionsplus_updater/trigger
GET  /event_tracing/*
GET  /settings/error                      (sub)
GET  /settings/events                     (sub)
```
