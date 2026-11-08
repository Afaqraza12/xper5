#!/usr/bin/env python3
import sys
import os

def patch_ksu(ksu_dir="ksu"):
    # 1. Patch hook_manager.c: avoid walking tasklist_lock with mismatched task_struct offsets
    hook_mgr_path = os.path.join(ksu_dir, "kernel/hook/hook_manager.c")
    if os.path.exists(hook_mgr_path):
        with open(hook_mgr_path, "r") as f:
            code = f.read()

        old_hpm = """static void handle_process_mark(bool mark)
{
\tstruct task_struct *p, *t;
\tread_lock(&tasklist_lock);
\tfor_each_process_thread(p, t) {
\t\tif (mark)
\t\t\tksu_set_task_tracepoint_flag(t);
\t\telse
\t\t\tksu_clear_task_tracepoint_flag(t);
\t}
\tread_unlock(&tasklist_lock);
}"""
        new_hpm = """static void handle_process_mark(bool mark)
{
\t(void)mark;
}"""
        if old_hpm in code:
            code = code.replace(old_hpm, new_hpm, 1)
            print("[+] Patched handle_process_mark in hook_manager.c")
        else:
            print("[-] Warning: handle_process_mark signature not matched exactly")

        old_mrpl_start = "static void ksu_mark_running_process_locked()"
        old_mrpl_end = "\tread_unlock(&tasklist_lock);\n}"
        start_idx = code.find(old_mrpl_start)
        if start_idx != -1:
            end_idx = code.find(old_mrpl_end, start_idx) + len(old_mrpl_end)
            code = code[:start_idx] + "static void ksu_mark_running_process_locked()\n{\n}" + code[end_idx:]
            print("[+] Patched ksu_mark_running_process_locked in hook_manager.c")
        else:
            print("[-] Warning: ksu_mark_running_process_locked signature not matched")

        with open(hook_mgr_path, "w") as f:
            f.write(code)

    # 2. Patch app_profile.c: avoid walking thread_group on unknown struct offset
    app_prof_path = os.path.join(ksu_dir, "kernel/policy/app_profile.c")
    if os.path.exists(app_prof_path):
        with open(app_prof_path, "r") as f:
            ap_code = f.read()

        old_ap = """#ifdef KSU_KPROBES_HOOK
    for_each_thread (p, t) {
        ksu_set_task_tracepoint_flag(t);
    }
#endif"""
        new_ap = """#ifdef KSU_KPROBES_HOOK
    ksu_set_task_tracepoint_flag(current);
#endif"""
        if old_ap in ap_code:
            ap_code = ap_code.replace(old_ap, new_ap, 1)
            print("[+] Patched app_profile.c for current task only")
        else:
            print("[-] Warning: app_profile.c loop not matched")

        with open(app_prof_path, "w") as f:
            f.write(ap_code)

    # 3. Patch core/init.c: prune allowlist without heavy blocking /data/app walk at late insmod,
    # and disable selinux_hide to prevent hooking /sys/fs/selinux/context (protects system services)
    init_path = os.path.join(ksu_dir, "kernel/core/init.c")
    if os.path.exists(init_path):
        with open(init_path, "r") as f:
            init_code = f.read()

        old_tt = "track_throne(false);"
        new_tt = "track_throne(true);"
        if old_tt in init_code:
            init_code = init_code.replace(old_tt, new_tt, 1)
            print("[+] Patched init.c to use prune-only track_throne at late insmod")

        old_shi = "ksu_selinux_hide_init();"
        new_shi = "/* ksu_selinux_hide_init(); */"
        if old_shi in init_code:
            init_code = init_code.replace(old_shi, new_shi, 1)
            print("[+] Disabled ksu_selinux_hide_init in init.c")

        with open(init_path, "w") as f:
            f.write(init_code)

    # 4. Patch manager/apk_sign.c: allow ReSukiSU and OriginSU manager packages
    apk_sign_path = os.path.join(ksu_dir, "kernel/manager/apk_sign.c")
    if os.path.exists(apk_sign_path):
        with open(apk_sign_path, "r") as f:
            sign_code = f.read()

        old_ima = """bool is_manager_apk(char *path)
{
\treturn check_v2_signature(path, EXPECTED_MANAGER_SIZE, EXPECTED_MANAGER_HASH);
}"""
        new_ima = """bool is_manager_apk(char *path)
{
\tchar pkg[KSU_MAX_PACKAGE_NAME];
\tif (get_pkg_from_apk_dir_path(pkg, path) == 0) {
\t\tif (!strcmp(pkg, "com.resukisu.resukisu") ||
\t\t    !strcmp(pkg, "com.originsu.manager") ||
\t\t    !strcmp(pkg, "me.weishu.kernelsu")) {
\t\t\tpr_info("Recognized manager apk: %s\\n", pkg);
\t\t\treturn true;
\t\t}
\t}
\treturn check_v2_signature(path, EXPECTED_MANAGER_SIZE, EXPECTED_MANAGER_HASH);
}"""
        if old_ima in sign_code:
            sign_code = sign_code.replace(old_ima, new_ima, 1)
            print("[+] Patched is_manager_apk to recognize ReSukiSU and OriginSU")
        else:
            print("[-] Warning: is_manager_apk signature not matched")

        with open(apk_sign_path, "w") as f:
            f.write(sign_code)

    # 5. Patch manager/throne_tracker.c: default manager appid to 10419 (ReSukiSU)
    tracker_path = os.path.join(ksu_dir, "kernel/manager/throne_tracker.c")
    if os.path.exists(tracker_path):
        with open(tracker_path, "r") as f:
            tt_code = f.read()

        old_app_id = "uid_t ksu_manager_appid = KSU_INVALID_APPID;"
        new_app_id = "uid_t ksu_manager_appid = 10419; // Default to ReSukiSU on SOG05"
        if old_app_id in tt_code:
            tt_code = tt_code.replace(old_app_id, new_app_id, 1)
            print("[+] Patched default ksu_manager_appid to 10419 in throne_tracker.c")
        else:
            print("[-] Warning: ksu_manager_appid signature not matched in throne_tracker.c")

        with open(tracker_path, "w") as f:
            f.write(tt_code)

if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "ksu"
    patch_ksu(target)
