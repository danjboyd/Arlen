#!/usr/bin/env python3
"""Regression coverage for comment-versus-command classification."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("classifier", Path(__file__).with_name("classify_sanitizer_integration_skips.py"))
classifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(classifier)


class CommentClassificationTests(unittest.TestCase):
    def test_comments_do_not_hide_or_invent_build_commands(self):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, "SyntheticTests.m").write_text('''@implementation SyntheticTests
- (void)testCommentOnly {
  // make clean and bin/boomhauer are words in a comment.
  /* tools/ci/example.sh is also a comment. */
  NSString *url = @"https://example.test/";
}
- (void)buildHelper {
  NSString *command = @"make clean";
}
- (void)testBuildCommand {
  [self buildHelper];
}
@end
''')
            self.assertEqual(["SyntheticTests/testBuildCommand"], classifier.classify(directory))


if __name__ == "__main__":
    unittest.main()
