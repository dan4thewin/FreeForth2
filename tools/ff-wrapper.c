/* ff-wrapper.c — guard against piped stdin, enforce file-only args.
 *
 * Compile with:  cc -DBINNAME="ff64" -o ff64- ff-wrapper.c
 *                cc -DBINNAME="ff"   -o ff-   ff-wrapper.c
 *
 * Resolves the real binary as a sibling of the wrapper's own location
 * (via /proc/self/exe), so it works from any CWD.
 */

#ifndef BINNAME
#error "Define BINNAME at compile time: cc -DBINNAME=\"ff64\" ..."
#endif

#define STR(x) STR_(x)
#define STR_(x) #x

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <poll.h>
#include <unistd.h>
#include <libgen.h>

int main(int argc, char **argv)
{
	struct stat st;
	int i;

	/* Resolve path to the real binary (sibling of this wrapper) */
	char self[4096];
	ssize_t len = readlink("/proc/self/exe", self, sizeof(self) - 1);
	if (len <= 0) {
		fprintf(stderr, "%s: error: cannot resolve /proc/self/exe\n", argv[0]);
		return 1;
	}
	self[len] = '\0';
	char *dir = dirname(self);
	char bin[4096];
	snprintf(bin, sizeof(bin), "%s/%s", dir, STR(BINNAME));

	if (argc < 2) {
		fprintf(stderr, "%s: error: no arguments. usage: %s file1.ff [file2.ff ...]\n",
			argv[0], argv[0]);
		return 1;
	}

	/* Validate every argument is a regular file */
	for (i = 1; i < argc; i++) {
		if (stat(argv[i], &st) != 0) {
			fprintf(stderr, "%s: error: cannot stat '%s': ",
				argv[0], argv[i]);
			perror(NULL);
			return 1;
		}
		if (!S_ISREG(st.st_mode)) {
			fprintf(stderr, "%s: error: '%s' is not a regular file. "
				"DO NOT PIPE TO THIS PROGRAM.\n",
				argv[0], argv[i]);
			return 1;
		}
	}

	/* Die loudly if anything is waiting on stdin */
	struct pollfd pfd = { .fd = STDIN_FILENO, .events = POLLIN };
	int ready = poll(&pfd, 1, 0);
	if (ready > 0 || (pfd.revents & (POLLIN | POLLHUP))) {
		fprintf(stderr,
			"%s: error: stdin has data or is a pipe. "
			"DO NOT PIPE TO THIS PROGRAM. "
			"Pass filenames as arguments instead.\n",
			argv[0]);
		return 1;
	}

	/* Close stdin so the child can't read it either */
	close(STDIN_FILENO);

	/* Build new argv: binary, -f, file1, -f, file2, ..., NULL */
	int nargs = 1 + (argc - 1) * 2 + 1;  /* bin + pairs + NULL */
	char **nargv = malloc(nargs * sizeof(char *));
	if (!nargv) {
		fprintf(stderr, "%s: error: malloc failed\n", argv[0]);
		return 1;
	}

	int j = 0;
	nargv[j++] = bin;
	for (i = 1; i < argc; i++) {
		nargv[j++] = "-f";
		nargv[j++] = argv[i];
	}
	nargv[j] = NULL;

	execv(bin, nargv);

	/* execv only returns on error */
	fprintf(stderr, "%s: error: execv '%s': ", argv[0], bin);
	perror(NULL);
	return 1;
}
