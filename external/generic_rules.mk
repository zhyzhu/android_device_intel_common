# prevent re-entrency (metatargets are calling them selves, e.g COPY_HEADERS)
ifeq ($(_metatarget),)
# get the name of the metatarget (which is the name of our symlink)
# it has to be very first place, because include will alter the MAKEFILE_LIST)
_metatarget := $(basename $(notdir $(call original-metatarget)))
_need_prebuilts :=
$(foreach project, $(_prebuilt_projects),\
  $(if $(findstring $(project), $(LOCAL_MODULE_MAKEFILE)),\
    $(eval _need_prebuilts := true)))

# Do not release prebuilts for tests modules
ifneq (,$(filter $(LOCAL_MODULE_TAGS), tests))
_need_prebuilts :=
endif

ifneq (,$(_need_prebuilts))
ifeq ($(findstring /PRIVATE/, $(LOCAL_MODULE_MAKEFILE)),)
$(error External framework does not support prebuilt for non PRIVATE path: $(LOCAL_MODULE_MAKEFILE))
_need_prebuilts :=
endif
endif

########################################################################################
ifneq (custom_external, $(_metatarget))
include $(call original-metatarget)
endif

########################################################################################

# do nothing more if we don't need prebuilts
ifneq (,$(_need_prebuilts))

# Record if this is a host module, to split host and target files in 2 different folders
# because a host and a target module can have same module name
ifeq ($(LOCAL_IS_HOST_MODULE), true)
    module_type :=  host
else
    module_type :=  target
endif

# transform the name of output dir,
# e.g. [/android_tree/]vendor/intel/PRIVATE/ipp -> vendor/intel/prebuilts/blackbay/ipp
# src makefile is renamed Android.mk in prebuilts out directory
_prj_path := $(dir $(patsubst $(ANDROID_BUILD_TOP)/%,%,$(LOCAL_MODULE_MAKEFILE)))
LOCAL_MODULE_PREBUILT_MAKEFILE := $(PRODUCT_OUT)/$(call intel-prebuilts-path,$(_prj_path))Android.mk
# local shortcut
my := $(LOCAL_MODULE_PREBUILT_MAKEFILE)

# we only define the commands once, even LOCAL_MODULE_PREBUILT_MAKEFILE may be defined
# via several metatargets (because the original Android.mk builds several things)

ifeq (,$($(LOCAL_MODULE_PREBUILT_MAKEFILE).ORIG_MAKEFILE))
$(LOCAL_MODULE_PREBUILT_MAKEFILE).ORIG_MAKEFILE := $(LOCAL_MODULE_MAKEFILE)
$(LOCAL_MODULE_PREBUILT_MAKEFILE).REF_PRODUCT_NAME := $(REF_PRODUCT_NAME)

# We only make one target to build the makefile (the ACPs are done in this target)
$(LOCAL_MODULE_PREBUILT_MAKEFILE): $(ACP) $(EXTERNAL_BUILD_SYSTEM)/generic_rules.mk
# cannot use $(LOCAL_MODULE_PREBUILT_MAKEFILE) or $(my) inside the rules, as they are expanded at rule running time
# while those two variables, are overriden at makefile parsing time
# we rebuild the whole directory every time to make sure there is no remaining files from previous build
# We don't remove the whole directory but only the files at first level, else we might have conflicts between
# cascaded Android.mk, when building with -j x option
	@mkdir -p $(dir $@)
	@find $(dir $@) -maxdepth 1 -type f -exec rm -f {} +
	@$(if $($@.copyfiles),\
		$(call copy-several-files, $($@.copyfiles)),)
	@echo '# autogenerated Android.mk' > $@
	@echo 'ifeq ($($@.REF_PRODUCT_NAME),$$(wildcard $($@.ORIG_MAKEFILE))$$(REF_PRODUCT_NAME))# test inexistance of original makefile, and correct ref product' >> $@
	@echo 'LOCAL_PATH := $$(call my-dir)' >> $@
	@$(foreach type, host target, \
		$(foreach class, PACKAGES PREBUILT LIBS EXECUTABLES JAVA_LIBRARIES STATIC_JAVA_LIBRARIES \
					HOST_LIBS HOST_EXECUTABLES HOST_JAVA_LIBRARIES HOST_STATIC_JAVA_LIBRARIES, \
			$(foreach module, $($@.$(type).$(class).LOCAL_INSTALLED_STEM_MODULES), \
				$(call external-auto-prebuilt-boilerplate, \
					$(type)/$($@.$(type).$(class).$(module).LOCAL_INSTALLED_MODULE_STEM), \
					$($@.$(type).$(class).$(module).LOCAL_IS_HOST_MODULE), \
					$($@.$(type).$(class).$(module).LOCAL_MODULE_CLASS), \
					$($@.$(type).$(class).$(module).LOCAL_MODULE_TAGS), \
					$($@.$(type).$(class).$(module).OVERRIDE_BUILT_MODULE_PATH), \
					$($@.$(type).$(class).$(module).LOCAL_UNINSTALLABLE_MODULE), \
					$($@.$(type).$(class).$(module).LOCAL_BUILT_MODULE_STEM), \
					$($@.$(type).$(class).$(module).LOCAL_STRIP_MODULE), \
					$($@.$(type).$(class).$(module).LOCAL_MODULE), \
					$($@.$(type).$(class).$(module).LOCAL_INSTALLED_MODULE_STEM), \
					$($@.$(type).$(class).$(module).LOCAL_CERTIFICATE), \
					$($@.$(type).$(class).$(module).LOCAL_MODULE_PATH), \
					$($@.$(type).$(class).$(module).LOCAL_REQUIRED_MODULES), \
					$($@.$(type).$(class).$(module).LOCAL_SHARED_LIBRARIES)))))
	@$(foreach to, $($@.headers_to), \
		$(if $(filter _none_,$(to)), \
			$(eval _to_:=),\
			$(eval _to_:=$(to))) \
		$(if $(strip $($@.headers.$(to))), \
			$(call external-echo-makefile, '') \
			$(call external-echo-makefile, 'include $$(CLEAR_VARS)') \
			$(call external-echo-makefile, 'LOCAL_COPY_HEADERS:=$(strip $($@.headers.$(to)))') \
			$(call external-echo-makefile, 'LOCAL_COPY_HEADERS_TO:=$(strip $(_to_))') \
			$(call external-echo-makefile, 'include $$(BUILD_COPY_HEADERS)')))
	@$(foreach mk, $($@.extramakefile), \
		$(call external-echo-makefile, '') \
		cat $(mk) >> $@;)
	@$(foreach module, $($@.phony), \
		$(call external-phony-package-boilerplate, \
			$(module), \
			$($@.phony.$(module).LOCAL_REQUIRED_MODULES)))
	@echo 'endif' >> $@
endif

# When odex is generated, .dex files are removed but .dex files should
# be saved for external release as they can be used to rebuild a component
# while odex can't.
# This is not necessary for java libraries that have unstripped jar in out/target/common.
# This requires patches in AOSP /build/ project to backup the .dex file.
EXT_JAVA_BACKUP_SUFFIX := .dex

# Prebuilts have complex way of finding source files with multilib.
# Unfortunately, the temporary variable used is reset in prebuilt_internal.mk
# so we have to replicate handling of the various cases here.
ifeq ($(_metatarget),prebuilt)
ifdef LOCAL_PREBUILT_MODULE_FILE
  ext_prebuilt_src_file := $(LOCAL_PREBUILT_MODULE_FILE)
else
  ifdef LOCAL_SRC_FILES_$($(my_prefix)$(LOCAL_2ND_ARCH_VAR_PREFIX)ARCH)
    ext_prebuilt_src_file := $(LOCAL_PATH)/$(LOCAL_SRC_FILES_$($(my_prefix)$(LOCAL_2ND_ARCH_VAR_PREFIX)ARCH))
  else
    ifdef LOCAL_SRC_FILES_$(my_32_64_bit_suffix)
      ext_prebuilt_src_file := $(LOCAL_PATH)/$(LOCAL_SRC_FILES_$(my_32_64_bit_suffix))
    else
      ext_prebuilt_src_file := $(LOCAL_PATH)/$(LOCAL_SRC_FILES)
    endif
  endif
endif
endif # $(_metatarget),prebuilt

ifeq ($(_metatarget),static_java_library)
ifneq (, $(wildcard $(common_javalib.jar)))
$(call external-gather-files,static_java_library,STATIC_JAVA_LIBRARIES)
generate_intel_prebuilts: $(LOCAL_MODULE_PREBUILT_MAKEFILE)
endif
endif

ifneq (, $(wildcard $(LOCAL_BUILT_MODULE)))
# this implement mapping between metatarget names, and what prebuilt is waiting for
$(call external-gather-files,executable,EXECUTABLES)
$(call external-gather-files,shared_library,LIBS)
$(call external-gather-files,static_library,LIBS)
$(call external-gather-files,host_executable,HOST_EXECUTABLES)
$(call external-gather-files,host_shared_library,HOST_LIBS)
$(call external-gather-files,host_static_library,HOST_LIBS)
$(call external-gather-files,java_library,JAVA_LIBRARIES)
$(call external-gather-files,package,PACKAGES,$(EXT_JAVA_BACKUP_SUFFIX))
$(call external-gather-files,prebuilt,PREBUILT)
generate_intel_prebuilts: $(LOCAL_MODULE_PREBUILT_MAKEFILE)
endif

# some metatargets also include copy_headers implicitly
ifneq ($(LOCAL_COPY_HEADERS),)
   generate_intel_prebuilts: $(LOCAL_MODULE_PREBUILT_MAKEFILE)
   $(my).copyfiles := $($(my).copyfiles) $(foreach h,$(LOCAL_COPY_HEADERS),$(LOCAL_PATH)/$(h):$(dir $(my))include/$(notdir $(h)))
ifeq ($(LOCAL_COPY_HEADERS_TO),)
   LOCAL_COPY_HEADERS_TO := _none_
endif
   $(my).headers_to := $($(my).headers_to) $(LOCAL_COPY_HEADERS_TO)
   $(my).headers.$(LOCAL_COPY_HEADERS_TO) := $($(my).headers.$(LOCAL_COPY_HEADERS_TO)) $(foreach h,$(LOCAL_COPY_HEADERS),include/$(notdir $(h)))
endif

ifneq ($(filter custom_external,$(_metatarget)),)
ifneq ($(LOCAL_BUILT_MODULE),)
   $(my).copyfiles := $($(my).copyfiles) $(LOCAL_BUILT_MODULE):$(dir $(my))$(module_type)/$(notdir $(LOCAL_BUILT_MODULE))
endif
   $(my).extramakefile := $($(my).extramakefile) $(LOCAL_PATH)/external_Android.mk
endif
# another special case with phony_package, which is a way to define a metapackage that justs
# depends on other packages
ifneq ($(filter phony_package,$(_metatarget)),)
ifneq (, $(wildcard $(LOCAL_BUILT_MODULE)))
   generate_intel_prebuilts: $(LOCAL_MODULE_PREBUILT_MAKEFILE)
   $(my).phony := $($(my).phony) $(LOCAL_MODULE)
   $(my).phony.$(LOCAL_MODULE).LOCAL_REQUIRED_MODULES := $(LOCAL_REQUIRED_MODULES)
endif
endif

###################################### dependencies #########################################
$(LOCAL_MODULE_PREBUILT_MAKEFILE): $(LOCAL_MODULE_MAKEFILE)
$(LOCAL_MODULE_PREBUILT_MAKEFILE): $(call several-files-deps, $($(LOCAL_MODULE_PREBUILT_MAKEFILE).copyfiles))

###################################### cleanups of local variables #########################################

# cleanup local shortcut for LOCAL_MODULE_PREBUILT_MAKEFILE
my :=
endif # is /PRIVATE/
_metatarget :=
_need_prebuilts :=
else # metatarget neq ''
include $(call original-metatarget)
endif
