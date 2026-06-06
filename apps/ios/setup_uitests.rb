#!/usr/bin/env ruby
# Adds a UI test target ("another-iptv-playerUITests") to the Xcode project
# and wires it into the existing shared scheme so fastlane snapshot can run it.
#
# Idempotent: re-running is a no-op once the target is present.

require "xcodeproj"

PROJECT_PATH        = File.expand_path("another-iptv-player.xcodeproj", __dir__)
APP_TARGET_NAME     = "another-iptv-player"
UITEST_TARGET_NAME  = "another-iptv-playerUITests"
UITEST_DIR          = File.expand_path(UITEST_TARGET_NAME, __dir__)

project = Xcodeproj::Project.open(PROJECT_PATH)
app_target = project.targets.find { |t| t.name == APP_TARGET_NAME }
abort "App target #{APP_TARGET_NAME} not found" unless app_target

app_settings = app_target.build_configurations.first.build_settings
dev_team     = app_settings["DEVELOPMENT_TEAM"]
app_bundle   = app_settings["PRODUCT_BUNDLE_IDENTIFIER"]
deploy_tgt   = app_settings["IPHONEOS_DEPLOYMENT_TARGET"] || "18.0"
swift_ver    = app_settings["SWIFT_VERSION"] || "5.0"

uitest_target = project.targets.find { |t| t.name == UITEST_TARGET_NAME }
if uitest_target.nil?
  uitest_target = project.new_target(
    :ui_test_bundle,
    UITEST_TARGET_NAME,
    :ios,
    deploy_tgt,
    project.products_group,
    :swift
  )
  uitest_target.add_dependency(app_target)
end

uitest_target.build_configurations.each do |config|
  bs = config.build_settings
  bs["PRODUCT_NAME"]               = "$(TARGET_NAME)"
  bs["PRODUCT_BUNDLE_IDENTIFIER"]  = "#{app_bundle}UITests"
  bs["DEVELOPMENT_TEAM"]           = dev_team if dev_team
  bs["TEST_TARGET_NAME"]           = APP_TARGET_NAME
  bs["SWIFT_VERSION"]              = swift_ver
  bs["CODE_SIGN_STYLE"]            = "Automatic"
  bs["IPHONEOS_DEPLOYMENT_TARGET"] = deploy_tgt
  bs["TARGETED_DEVICE_FAMILY"]     = "1,2"
  bs["GENERATE_INFOPLIST_FILE"]    = "YES"
end

# Reference the UITest source folder + files
group = project.main_group.find_subpath(UITEST_TARGET_NAME, true)
group.set_source_tree("<group>")
group.set_path(UITEST_TARGET_NAME)

Dir.glob(File.join(UITEST_DIR, "*.swift")).each do |path|
  filename  = File.basename(path)
  file_ref  = group.files.find { |f| f.path == filename } || group.new_reference(filename)
  uitest_target.add_file_references([file_ref]) unless uitest_target.source_build_phase.files_references.include?(file_ref)
end

project.save

# Wire the new UITest target into the shared scheme so fastlane snapshot can find it.
shared_dir = Xcodeproj::XCScheme.shared_data_dir(PROJECT_PATH)
scheme_path = File.join(shared_dir, "#{APP_TARGET_NAME}.xcscheme")
abort "Scheme not found at #{scheme_path}" unless File.exist?(scheme_path)

scheme = Xcodeproj::XCScheme.new(scheme_path)
already_in_scheme = scheme.test_action.testables.any? { |t| t.buildable_references.any? { |br| br.target_name == UITEST_TARGET_NAME } }
unless already_in_scheme
  testable = Xcodeproj::XCScheme::TestAction::TestableReference.new(uitest_target)
  scheme.test_action.add_testable(testable)
  scheme.save_as(PROJECT_PATH, APP_TARGET_NAME, true)
end

puts "Added #{UITEST_TARGET_NAME} target and wired it into the #{APP_TARGET_NAME} scheme."
