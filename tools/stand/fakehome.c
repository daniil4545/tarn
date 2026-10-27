// Test-only interpose: the passwd home directory of the current user becomes $FAKE_PW_DIR.
// Lets a second copy of the app own its own control socket next to the user's running Tarn.
#include <pwd.h>
#include <stdlib.h>
#include <unistd.h>

#define INTERPOSE(replacement, original) \
    __attribute__((used)) static struct { const void *r; const void *o; } _i_##original \
    __attribute__((section("__DATA,__interpose"))) = { (const void *)replacement, (const void *)original }

static void fix(struct passwd *pw) {
    const char *dir = getenv("FAKE_PW_DIR");
    if (pw && dir && pw->pw_uid == getuid()) pw->pw_dir = (char *)dir;
}

static struct passwd *my_getpwuid(uid_t uid) {
    struct passwd *pw = getpwuid(uid);
    fix(pw);
    return pw;
}

static int my_getpwuid_r(uid_t uid, struct passwd *pw, char *buf, size_t len, struct passwd **out) {
    int rc = getpwuid_r(uid, pw, buf, len, out);
    if (rc == 0 && out) fix(*out);
    return rc;
}

static struct passwd *my_getpwnam(const char *name) {
    struct passwd *pw = getpwnam(name);
    fix(pw);
    return pw;
}

static int my_getpwnam_r(const char *name, struct passwd *pw, char *buf, size_t len, struct passwd **out) {
    int rc = getpwnam_r(name, pw, buf, len, out);
    if (rc == 0 && out) fix(*out);
    return rc;
}

INTERPOSE(my_getpwuid, getpwuid);
INTERPOSE(my_getpwuid_r, getpwuid_r);
INTERPOSE(my_getpwnam, getpwnam);
INTERPOSE(my_getpwnam_r, getpwnam_r);
