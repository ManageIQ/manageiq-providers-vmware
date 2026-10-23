package parser

import "testing"

func TestCGIUnescape(t *testing.T) {
	tests := []struct{ in, want string }{
		{"a%20b+c", "a b c"},
		{"%2", "%2"},
		{"%zz", "%zz"},
		{"100%", "100%"},
		{"%E2%82%AC", "\u20ac"},
		{"x%2Fy", "x/y"},
		{"%%41", "%A"},
		{"plain", "plain"},
		{"%e9", "%e9"}, // divergence: invalid UTF-8
	}

	for _, tt := range tests {
		if got := cgiUnescape(tt.in); got != tt.want {
			t.Errorf("cgiUnescape(%q) = %q, want %q", tt.in, got, tt.want)
		}
	}
}
