/* translation of bf.s in C */

#include <sys/mman.h>
#include <fcntl.h>
#include <stdint.h>
#include <unistd.h>

#define MAX_CODESIZE 32768 /* myst be an integral multiple of the page size */

uint8_t data[65536];
uint8_t *stack[4096];

#define die(s)                                                                \
	do {                                                                  \
		write(STDERR_FILENO, s, sizeof(s) - 1);                       \
		return 1;                                                     \
	} while (0)

int
main(int argc, char *argv[])
{
	size_t bracket_counter;
	uint16_t data_idx = 0;
	uint8_t *instruction, top = 0;
	int fd;

	if (argc != 2)
		die("usage: bf file.b\n");

	if ((fd = open(argv[1], O_RDONLY)) < 0)
		die("error: failed to open file\n");
	instruction = mmap(0, MAX_CODESIZE, PROT_READ, MAP_PRIVATE, fd, 0);
	close(fd);

	for (;;) {
		switch (*instruction) {
		case '>':
			data_idx++;
			break;
		case '<':
			data_idx--;
			break;
		case '+':
			data[data_idx]++;
			break;
		case '-':
			data[data_idx]--;
			break;
		case '[':
			if (data[data_idx] == 0) {
				bracket_counter = 1;
				do {
					instruction++;
					if (*instruction == '[')
						bracket_counter++;
					else if (*instruction == ']')
						bracket_counter--;
				} while (bracket_counter != 0);
			} else {
				stack[top] = instruction;
				top++;
			}
			break;
		case ']':
			if (data[data_idx] != 0)
				instruction = stack[top - 1];
			else
				top--;
			break;
		case '.':
			write(STDOUT_FILENO, &data[data_idx], 1);
			break;
		case ',':
			read(STDIN_FILENO, &data[data_idx], 1);
			break;
		case '\0':
			return 0;
		}
		instruction++;
	}

	/* unreachable */
}
