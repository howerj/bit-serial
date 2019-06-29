#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <ctype.h>

char *trimleft(char *s) {
	while (isspace(*s))
		s++;
	return s;
}

void trimright(char *s) {
	size_t l = strlen(s);
	if (!l)
		return;
	s += l - 1;
	while (l && isspace(*s))
		s--, l--;
	*(s+1) = 0;
}

char *trim(char *s) {
	char *r = trimleft(s);
	trimright(r);
	return r;
}

int main(void) {
	for (char buf[80] = { 0 }; fgets(buf + 1, sizeof buf - 1, stdin); memset(buf, 0, sizeof buf)) {
		char *s = trim(buf + 1);
		const size_t l = strlen(s);
		if (l > 255)
			return -1;
		*(--s) = l;
		for (size_t i = 0; i < (l + 1); i += 2)
			fprintf(stdout, "%02x%02x ", s[i + 1], s[i]);
		fprintf(stdout, "; %d '%s'\n", *s, s+1);
		fflush(stdout);
	}
	return 0;
}

