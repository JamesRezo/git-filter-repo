#!/bin/bash

test_description='Basic filter-repo tests'

. ./test-lib.sh

export PATH=$(dirname $TEST_DIRECTORY):$PATH  # Put git-filter-repo in PATH

DATA="$TEST_DIRECTORY/t9390"
SQ="'"

filter_testcase() {
	INPUT=$1
	OUTPUT=$2
	shift 2
	REST=("$@")


	NAME="check: $INPUT -> $OUTPUT using '${REST[@]}'"
	test_expect_success "$NAME" '
		# Clean up from previous run
		git pack-refs --all &&
		rm .git/packed-refs &&

		# Run the example
		cat $DATA/$INPUT | git filter-repo --stdin --quiet --force --replace-refs delete-no-add "${REST[@]}" &&

		# Compare the resulting repo to expected value
		git fast-export --use-done-feature --all >compare &&
		test_cmp $DATA/$OUTPUT compare
	'
}

filter_testcase basic basic-filename --path filename
filter_testcase basic basic-twenty   --path twenty
filter_testcase basic basic-ten      --path ten
filter_testcase basic basic-numbers  --path ten --path twenty
filter_testcase basic basic-filename --invert-paths --path-glob 't*en*'
filter_testcase basic basic-numbers  --invert-paths --path-regex 'f.*e.*e'
filter_testcase basic basic-mailmap  --mailmap ../t9390/sample-mailmap
filter_testcase basic basic-replace  --replace-text ../t9390/sample-replace
filter_testcase empty empty-keepme   --path keepme
filter_testcase empty more-empty-keepme --path keepme --prune-empty=always \
		                                   --prune-degenerate=always
filter_testcase empty less-empty-keepme --path keepme --prune-empty=never \
		                                   --prune-degenerate=never
filter_testcase degenerate degenerate-keepme   --path moduleA/keepme
filter_testcase degenerate degenerate-moduleA  --path moduleA
filter_testcase degenerate degenerate-globme   --path-glob *me
filter_testcase unusual unusual-filtered --path ''
filter_testcase unusual unusual-mailmap  --mailmap ../t9390/sample-mailmap

test_expect_success 'setup path_rename' '
	test_create_repo path_rename &&
	(
		cd path_rename &&
		mkdir sequences values &&
		test_seq 1 10 >sequences/tiny &&
		test_seq 100 110 >sequences/intermediate &&
		test_seq 1000 1010 >sequences/large &&
		test_seq 1000 1010 >values/large &&
		test_seq 10000 10010 >values/huge &&
		git add sequences values &&
		git commit -m initial &&

		git mv sequences/tiny sequences/small &&
		cp sequences/intermediate sequences/medium &&
		echo 10011 >values/huge &&
		git add sequences values &&
		git commit -m updates &&

		git rm sequences/intermediate &&
		echo 11 >sequences/small &&
		git add sequences/small &&
		git commit -m changes &&

		echo 1011 >sequences/medium &&
		git add sequences/medium &&
		git commit -m final
	)
'

test_expect_success '--path-rename sequences/tiny:sequences/small' '
	(
		git clone file://"$(pwd)"/path_rename path_rename_single &&
		cd path_rename_single &&
		git filter-repo --path-rename sequences/tiny:sequences/small &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		test_line_count = 7 filenames &&
		! grep sequences/tiny filenames &&
		git rev-parse HEAD~3:sequences/small
	)
'

test_expect_success '--path-rename sequences:numbers' '
	(
		git clone file://"$(pwd)"/path_rename path_rename_dir &&
		cd path_rename_dir &&
		git filter-repo --path-rename sequences:numbers &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		test_line_count = 8 filenames &&
		! grep sequences/ filenames &&
		grep numbers/ filenames &&
		grep values/ filenames
	)
'

test_expect_success '--path-rename-prefix values:numbers' '
	(
		git clone file://"$(pwd)"/path_rename path_rename_dir_2 &&
		cd path_rename_dir_2 &&
		git filter-repo --path-rename values/:numbers/ &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		test_line_count = 8 filenames &&
		! grep values/ filenames &&
		grep sequences/ filenames &&
		grep numbers/ filenames
	)
'

test_expect_success '--path-rename squashing' '
	(
		git clone file://"$(pwd)"/path_rename path_rename_squash &&
		cd path_rename_squash &&
		git filter-repo \
			--path-rename sequences/tiny:sequences/small \
			--path-rename sequences:numbers \
			--path-rename values:numbers \
			--path-rename numbers/intermediate:numbers/medium &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		# Just small, medium, large, huge, and a blank line...
		test_line_count = 5 filenames &&
		! grep sequences/ filenames &&
		! grep values/ filenames &&
		grep numbers/ filenames
	)
'

test_expect_success '--path-rename inability to squash' '
	(
		git clone file://"$(pwd)"/path_rename path_rename_bad_squash &&
		cd path_rename_bad_squash &&
		test_must_fail git filter-repo \
			--path-rename values/large:values/big \
			--path-rename values/huge:values/big 2>../err &&
		test_i18ngrep "File renaming caused colliding pathnames" ../err
	)
'

test_expect_success '--paths-from-file' '
	(
		git clone file://"$(pwd)"/path_rename paths_from_file &&
		cd paths_from_file &&

		cat >../path_changes <<-EOF &&
		literal:values/huge
		values/huge==>values/gargantuan
		glob:*rge

		regex:.*med.*
		regex:^([^/]*)/(.*)ge$==>\2/\1/ge
		EOF

		git filter-repo --paths-from-file ../path_changes &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		# intermediate, medium, two larges, gargantuan, and a blank line
		test_line_count = 6 filenames &&
		! grep sequences/tiny filenames &&
		grep sequences/intermediate filenames &&
		grep lar/sequences/ge filenames &&
		grep lar/values/ge filenames &&
		grep values/gargantuan filenames &&
		! grep sequences/small filenames &&
		grep sequences/medium filenames &&

		rm ../path_changes
	)
'

test_expect_success 'setup metasyntactic repo' '
	test_create_repo metasyntactic &&
	(
		cd metasyntactic &&
		weird_name=$(printf "file\tna\nme") &&
		echo "funny" >"$weird_name" &&
		mkdir numbers &&
		test_seq 1 10 >numbers/small &&
		test_seq 100 110 >numbers/medium &&
		git add "$weird_name" numbers &&
		git commit -m initial &&
		git tag v1.0 &&
		git tag -a -m v1.1 v1.1 &&

		mkdir words &&
		echo foo >words/important &&
		echo bar >words/whimsical &&
		echo baz >words/sequences &&
		git add words &&
		git commit -m some.words &&
		git branch another_branch &&
		git tag v2.0 &&

		echo spam >words/to &&
		echo eggs >words/know &&
		git add words
		git rm "$weird_name" &&
		git commit -m more.words &&
		git tag -a -m "Look, ma, I made a tag" v3.0
	)
'

test_expect_success '--tag-rename' '
	(
		git clone file://"$(pwd)"/metasyntactic tag_rename &&
		cd tag_rename &&
		git filter-repo \
			--tag-rename "":"myrepo-" \
			--path words &&
		test_must_fail git cat-file -t v1.0 &&
		test_must_fail git cat-file -t v1.1 &&
		test_must_fail git cat-file -t v2.0 &&
		test_must_fail git cat-file -t v3.0 &&
		test_must_fail git cat-file -t myrepo-v1.0 &&
		test_must_fail git cat-file -t myrepo-v1.1 &&
		test $(git cat-file -t myrepo-v2.0) = commit &&
		test $(git cat-file -t myrepo-v3.0) = tag
	)
'

test_expect_success '--subdirectory-filter' '
	(
		git clone file://"$(pwd)"/metasyntactic subdir_filter &&
		cd subdir_filter &&
		git filter-repo \
			--subdirectory-filter words &&
		git cat-file --batch-check --batch-all-objects >all-objs &&
		test_line_count = 10 all-objs &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		test_line_count = 6 filenames &&
		grep ^important$ filenames &&
		test_must_fail git cat-file -t v1.0 &&
		test_must_fail git cat-file -t v1.1 &&
		test $(git cat-file -t v2.0) = commit &&
		test $(git cat-file -t v3.0) = tag
	)
'

test_expect_success '--to-subdirectory-filter' '
	(
		git clone file://"$(pwd)"/metasyntactic to_subdir_filter &&
		cd to_subdir_filter &&
		git filter-repo \
			--to-subdirectory-filter mysubdir &&
		git cat-file --batch-check --batch-all-objects >all-objs &&
		test_line_count = 22 all-objs &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		test_line_count = 9 filenames &&
		grep "^\"mysubdir/file\\\\tna\\\\nme\"$" filenames &&
		grep ^mysubdir/words/important$ filenames &&
		test $(git cat-file -t v1.0) = commit &&
		test $(git cat-file -t v1.1) = tag &&
		test $(git cat-file -t v2.0) = commit &&
		test $(git cat-file -t v3.0) = tag
	)
'

test_expect_success '--use-base-name' '
	(
		git clone file://"$(pwd)"/metasyntactic use_base_name &&
		cd use_base_name &&
		git filter-repo --path small --path important --use-base-name &&
		git cat-file --batch-check --batch-all-objects >all-objs &&
		test_line_count = 10 all-objs &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		test_line_count = 3 filenames &&
		grep ^numbers/small$ filenames &&
		grep ^words/important$ filenames &&
		test $(git cat-file -t v1.0) = commit &&
		test $(git cat-file -t v1.1) = tag &&
		test $(git cat-file -t v2.0) = commit &&
		test $(git cat-file -t v3.0) = tag
	)
'

test_expect_success 'refs/replace/ to skip a parent' '
	(
		git clone file://"$(pwd)"/metasyntactic replace_skip_ref &&
		cd replace_skip_ref &&

		git tag -d v2.0 &&
		git replace HEAD~1 HEAD~2 &&

		git filter-repo --replace-refs delete-no-add --path "" --force &&
		test $(git rev-list --count HEAD) = 2 &&
		git cat-file --batch-check --batch-all-objects >all-objs &&
		test_line_count = 16 all-objs &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		test_line_count = 9 filenames &&
		test $(git cat-file -t v1.0) = commit &&
		test $(git cat-file -t v1.1) = tag &&
		test_must_fail git cat-file -t v2.0 &&
		test $(git cat-file -t v3.0) = tag
	)
'

test_expect_success 'refs/replace/ to add more initial history' '
	(
		git clone file://"$(pwd)"/metasyntactic replace_add_refs &&
		cd replace_add_refs &&

		git checkout --orphan new_root &&
		rm .git/index &&
		git add numbers/small &&
		git clean -fd &&
		git commit -m new.root &&

		git replace --graft master~2 new_root &&
		git checkout master &&

		git --no-replace-objects cat-file -p master~2 >grandparent &&
		! grep parent grandparent &&

		git filter-repo --replace-refs delete-no-add --path "" --force &&

		git --no-replace-objects cat-file -p master~2 >new-grandparent &&
		grep parent new-grandparent &&

		test $(git rev-list --count HEAD) = 4 &&
		git cat-file --batch-check --batch-all-objects >all-objs &&
		test_line_count = 22 all-objs &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		test_line_count = 9 filenames &&
		test $(git cat-file -t v1.0) = commit &&
		test $(git cat-file -t v1.1) = tag &&
		test $(git cat-file -t v2.0) = commit &&
		test $(git cat-file -t v3.0) = tag
	)
'

test_expect_success 'creation/deletion/updating of replace refs' '
	(
		git clone file://"$(pwd)"/metasyntactic replace_handling &&

		# Same setup as "refs/replace/ to skip a parent", so we
		# do not have to check that replacement refs were used
		# correctly in the rewrite, just that replacement refs were
		# deleted, added, or updated correctly.
		cd replace_handling &&
		git tag -d v2.0 &&
		master=$(git rev-parse master) &&
		master_1=$(git rev-parse master~1) &&
		master_2=$(git rev-parse master~2) &&
		git replace HEAD~1 HEAD~2 &&
		cd .. &&

		mkdir -p test_replace_refs &&
		cd test_replace_refs &&

		rsync -a --delete ../replace_handling/ ./ &&
		git filter-repo --replace-refs delete-no-add --path-rename numbers:counting &&
		git show-ref >output &&
		! grep refs/replace/ output &&

		rsync -a --delete ../replace_handling/ ./ &&
		git filter-repo --replace-refs delete-and-add --path-rename numbers:counting &&
		echo "$(git rev-parse master) refs/replace/$master" >out &&
		echo "$(git rev-parse master~1) refs/replace/$master_1" >>out &&
		echo "$(git rev-parse master~1) refs/replace/$master_2" >>out &&
		sort -k 2 out >expect &&
		git show-ref | grep refs/replace/ >output &&
		test_cmp output expect &&

		rsync -a --delete ../replace_handling/ ./ &&
		git filter-repo --replace-refs update-no-add --path-rename numbers:counting &&
		echo "$(git rev-parse master~1) refs/replace/$master_1" >expect &&
		git show-ref | grep refs/replace/ >output &&
		test_cmp output expect &&

		rsync -a --delete ../replace_handling/ ./ &&
		git filter-repo --replace-refs update-or-add --path-rename numbers:counting &&
		echo "$(git rev-parse master) refs/replace/$master" >>out &&
		echo "$(git rev-parse master~1) refs/replace/$master_1" >>out &&
		sort -k 2 out >expect &&
		git show-ref | grep refs/replace/ >output &&
		test_cmp output expect &&

		rsync -a --delete ../replace_handling/ ./ &&
		git filter-repo --replace-refs update-and-add --path-rename numbers:counting &&
		echo "$(git rev-parse master) refs/replace/$master" >>out &&
		echo "$(git rev-parse master~1) refs/replace/$master_1" >>out &&
		echo "$(git rev-parse master~1) refs/replace/$master_2" >>out &&
		sort -k 2 out >expect &&
		git show-ref | grep refs/replace/ >output &&
		test_cmp output expect
	)
'

test_expect_success '--debug' '
	(
		git clone file://"$(pwd)"/metasyntactic debug &&
		cd debug &&

		git filter-repo --path words --debug &&

		test $(git rev-list --count HEAD) = 2 &&
		git cat-file --batch-check --batch-all-objects >all-objs &&
		test_line_count = 12 all-objs &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		test_line_count = 6 filenames &&

		test_path_is_file .git/filter-repo/fast-export.original &&
		grep "^commit " .git/filter-repo/fast-export.original >out &&
		test_line_count = 3 out &&
		test_path_is_file .git/filter-repo/fast-export.filtered &&
		grep "^commit " .git/filter-repo/fast-export.filtered >out &&
		test_line_count = 2 out
	)
'

test_expect_success '--dry-run' '
	(
		git clone file://"$(pwd)"/metasyntactic dry_run &&
		cd dry_run &&

		git filter-repo --path words --dry-run &&

		git show-ref | grep master >out &&
		test_line_count = 2 out &&
		awk "{print \$1}" out | uniq >out2 &&
		test_line_count = 1 out2 &&

		test $(git rev-list --count HEAD) = 3 &&
		git cat-file --batch-check --batch-all-objects >all-objs &&
		test_line_count = 19 all-objs &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		test_line_count = 9 filenames &&

		test_path_is_file .git/filter-repo/fast-export.original &&
		grep "^commit " .git/filter-repo/fast-export.original >out &&
		test_line_count = 3 out &&
		test_path_is_file .git/filter-repo/fast-export.filtered &&
		grep "^commit " .git/filter-repo/fast-export.filtered >out &&
		test_line_count = 2 out
	)
'

test_expect_success '--dry-run --stdin' '
	(
		git clone file://"$(pwd)"/metasyntactic dry_run_stdin &&
		cd dry_run_stdin &&

		git fast-export --all | git filter-repo --path words --dry-run --stdin &&

		git show-ref | grep master >out &&
		test_line_count = 2 out &&
		awk "{print \$1}" out | uniq >out2 &&
		test_line_count = 1 out2 &&

		test $(git rev-list --count HEAD) = 3 &&
		git cat-file --batch-check --batch-all-objects >all-objs &&
		test_line_count = 19 all-objs &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		test_line_count = 9 filenames &&

		test_path_is_missing .git/filter-repo/fast-export.original &&
		test_path_is_file .git/filter-repo/fast-export.filtered &&
		grep "^commit " .git/filter-repo/fast-export.filtered >out &&
		test_line_count = 2 out
	)
'

test_expect_success 'setup analyze_me' '
	test_create_repo analyze_me &&
	(
		cd analyze_me &&
		mkdir numbers words &&
		test_seq 1 10 >numbers/small.num &&
		test_seq 100 110 >numbers/medium.num &&
		echo spam >words/to &&
		echo eggs >words/know &&
		echo rename a lot >fickle &&
		git add numbers words fickle &&
		test_tick &&
		git commit -m initial &&

		git branch other &&
		git mv fickle capricious &&
		test_tick &&
		git commit -m "rename on main branch" &&

		git checkout other &&
		echo random other change >whatever &&
		git add whatever &&
		git mv fickle capricious &&
		test_tick &&
		git commit -m "rename on other branch" &&

		git checkout master &&
		git merge --no-commit other &&
		git mv capricious mercurial &&
		test_tick &&
		git commit &&

		git mv words sequence &&
		test_tick &&
		git commit -m now.sequence &&

		git rm -rf numbers &&
		test_tick &&
		git commit -m remove.words &&

		mkdir words &&
		echo no >words/know &&
		git add words/know &&
		test_tick &&
		git commit -m "Recreated file previously renamed" &&

		echo "160000 deadbeefdeadbeefdeadbeefdeadbeefdeadbeefQfake_submodule" | q_to_tab | git update-index --index-info &&
		test_tick &&
		git commit -m "Add a fake submodule" &&

		test_tick &&
		git commit --allow-empty -m "Final commit, empty" &&

		# Add a random extra unreferenced object
		echo foobar | git hash-object --stdin -w
	)
'

test_expect_success C_LOCALE_OUTPUT '--analyze' '
	(
		cd analyze_me &&

		git filter-repo --analyze &&

		# It should work and overwrite report if run again
		git filter-repo --analyze &&

		test -d .git/filter-repo/analysis &&
		cd .git/filter-repo/analysis &&

		cat >expect <<-EOF &&
		fickle ->
		    capricious
		    mercurial
		words/to ->
		    sequence/to
		EOF
		test_cmp expect renames.txt &&

		cat >expect <<-EOF &&
		== Overall Statistics ==
		  Number of commits: 9
		  Number of filenames: 10
		  Number of directories: 4
		  Number of file extensions: 2

		  Total unpacked size (bytes): 147
		  Total packed size (bytes): 306

		EOF
		head -n 9 README >actual &&
		test_cmp expect actual &&

		cat >expect <<-\EOF &&
		=== Files by sha and associated pathnames in reverse size ===
		Format: sha, unpacked size, packed size, filename(s) object stored as
		  a89c82a2d4b713a125a4323d25adda062cc0013d         44         48 numbers/medium.num
		  f00c965d8307308469e537302baa73048488f162         21         37 numbers/small.num
		  2aa69a2a708eed00cb390e30f6bcc3eed773f390         20         36 whatever
		  51b95456de9274c9a95f756742808dfd480b9b35         13         29 [capricious, fickle, mercurial]
		  732c85a1b3d7ce40ec8f78fd9ffea32e9f45fae0          5         20 [sequence/know, words/know]
		  34b6a0c9d02cb6ef7f409f248c0c1224ce9dd373          5         20 [sequence/to, words/to]
		  7ecb56eb3fa3fa6f19dd48bca9f971950b119ede          3         18 words/know
		EOF
		test_cmp expect blob-shas-and-paths.txt &&

		cat >expect <<-EOF &&
		=== All directories by reverse size ===
		Format: unpacked size, packed size, date deleted, directory name
		         147        306 <present>  <toplevel>
		          65         85 2005-04-07 numbers
		          13         58 <present>  words
		          10         40 <present>  sequence
		EOF
		test_cmp expect directories-all-sizes.txt &&

		cat >expect <<-EOF &&
		=== Deleted directories by reverse size ===
		Format: unpacked size, packed size, date deleted, directory name
		          65         85 2005-04-07 numbers
		EOF
		test_cmp expect directories-deleted-sizes.txt &&

		cat >expect <<-EOF &&
		=== All extensions by reverse size ===
		Format: unpacked size, packed size, date deleted, extension name
		          82        221 <present>  <no extension>
		          65         85 2005-04-07 .num
		EOF
		test_cmp expect extensions-all-sizes.txt &&

		cat >expect <<-EOF &&
		=== Deleted extensions by reverse size ===
		Format: unpacked size, packed size, date deleted, extension name
		          65         85 2005-04-07 .num
		EOF
		test_cmp expect extensions-deleted-sizes.txt &&

		cat >expect <<-EOF &&
		=== All paths by reverse accumulated size ===
		Format: unpacked size, packed size, date deleted, pathectory name
		          44         48 2005-04-07 numbers/medium.num
		           8         38 <present>  words/know
		          21         37 2005-04-07 numbers/small.num
		          20         36 <present>  whatever
		          13         29 <present>  mercurial
		          13         29 <present>  fickle
		          13         29 <present>  capricious
		           5         20 <present>  words/to
		           5         20 <present>  sequence/to
		           5         20 <present>  sequence/know
		EOF
		test_cmp expect path-all-sizes.txt &&

		cat >expect <<-EOF &&
		=== Deleted paths by reverse accumulated size ===
		Format: unpacked size, packed size, date deleted, path name(s)
		          44         48 2005-04-07 numbers/medium.num
		          21         37 2005-04-07 numbers/small.num
		EOF
		test_cmp expect path-deleted-sizes.txt
	)
'

test_expect_success '--replace-text all options' '
	(
		git clone file://"$(pwd)"/analyze_me replace_text &&
		cd replace_text &&

		cat >../replace-rules <<-\EOF &&
		other
		change==>variation

		literal:spam==>foodstuff
		glob:ran*m==>haphazard
		regex:1(.[0-9])==>2\1
		EOF
		git filter-repo --replace-text ../replace-rules &&

		test_seq 200 210 >expect &&
		git show HEAD~4:numbers/medium.num >actual &&
		test_cmp expect actual &&

		echo "haphazard ***REMOVED*** variation" >expect &&
		test_cmp expect whatever
	)
'

test_expect_success '--strip-blobs-bigger-than' '
	(
		git clone file://"$(pwd)"/analyze_me strip_big_blobs &&
		cd strip_big_blobs &&

		# Verify certain files are present initially
		git log --format=%n --name-only | sort | uniq >../filenames &&
		test_line_count = 11 ../filenames &&
		git rev-parse HEAD~7:numbers/medium.num &&
		git rev-parse HEAD~7:numbers/small.num &&
		git rev-parse HEAD~4:mercurial &&
		test -f mercurial &&

		# Make one of the current files be "really big"
		test_seq 1 1000 >mercurial &&
		git add mercurial &&
		git commit --amend &&

		# Strip "really big" files
		git filter-repo --force --strip-blobs-bigger-than 3K --prune-empty never &&

		git log --format=%n --name-only | sort | uniq >../filenames &&
		test_line_count = 11 ../filenames &&
		# The "mercurial" file should still be around...
		git rev-parse HEAD~4:mercurial &&
		git rev-parse HEAD:mercurial &&
		# ...but only with its old, smaller contents
		test_line_count = 1 mercurial &&

		# Strip files that are too big, verify they are gone
		git filter-repo --strip-blobs-bigger-than 40 &&

		git log --format=%n --name-only | sort | uniq >../filenames &&
		test_line_count = 10 ../filenames &&
		test_must_fail git rev-parse HEAD~7:numbers/medium.num &&

		# Do it again, this time with --replace-text since that means
		# we are operating without --no-data and have to go through
		# a different codepath.  (The search/replace terms are bogus)
		cat >../replace-rules <<-\EOF &&
		not found==>was found
		EOF
		git filter-repo --strip-blobs-bigger-than 20 --replace-text ../replace-rules &&

		git log --format=%n --name-only | sort | uniq >../filenames &&
		test_line_count = 9 ../filenames &&
		test_must_fail git rev-parse HEAD~7:numbers/medium.num &&
		test_must_fail git rev-parse HEAD~7:numbers/small.num &&

		# Remove the temporary auxiliary files
		rm ../replace-rules &&
		rm ../filenames
	)
'

test_expect_success '--strip-blobs-with-ids' '
	(
		git clone file://"$(pwd)"/analyze_me strip_blobs_with_ids &&
		cd strip_blobs_with_ids &&

		# Verify certain files are present initially
		git log --format=%n --name-only | sort | uniq >../filenames &&
		test_line_count = 11 ../filenames &&
		grep fake_submodule ../filenames &&

		# Strip "a certain file" files
		git filter-repo --strip-blobs-with-ids <(echo deadbeefdeadbeefdeadbeefdeadbeefdeadbeef) &&

		git log --format=%n --name-only | sort | uniq >../filenames &&
		test_line_count = 10 ../filenames &&
		# Make sure fake_submodule was removed
		! grep fake_submodule ../filenames &&

		# Do it again, this time with --replace-text since that means
		# we are operating without --no-data and have to go through
		# a different codepath.  (The search/replace terms are bogus)
		cat >../bad-ids <<-\EOF &&
		34b6a0c9d02cb6ef7f409f248c0c1224ce9dd373
		51b95456de9274c9a95f756742808dfd480b9b35
		EOF
		cat >../replace-rules <<-\EOF &&
		not found==>was found
		EOF
		git filter-repo --strip-blobs-with-ids ../bad-ids --replace-text ../replace-rules &&

		git log --format=%n --name-only | sort | uniq >../filenames &&
		test_line_count = 5 ../filenames &&
		! grep sequence/to ../filenames &&
		! grep words/to ../filenames &&
		! grep capricious ../filenames &&
		! grep fickle ../filenames &&
		! grep mercurial ../filenames

		# Remove the temporary auxiliary files
		rm ../bad-ids &&
		rm ../replace-rules &&
		rm ../filenames
	)
'

test_expect_success 'setup commit message rewriting' '
	test_create_repo commit_msg &&
	(
		cd commit_msg &&
		echo two guys walking into a >bar &&
		git add bar &&
		git commit -m initial &&

		test_commit another &&

		name=$(git rev-parse HEAD) &&
		echo hello >world &&
		git add world &&
		git commit -m "Commit referencing ${name:0:8}" &&

		git revert HEAD &&

		for i in $(test_seq 1 200)
		do
			git commit --allow-empty -m "another commit"
		done &&

		echo foo >bar &&
		git add bar &&
		git commit -m bar &&

		git revert --no-commit HEAD &&
		echo foo >baz &&
		git add baz &&
		git commit
	)
'

test_expect_success 'commit message rewrite' '
	(
		git clone file://"$(pwd)"/commit_msg commit_msg_clone &&
		cd commit_msg_clone &&

		git filter-repo --invert-paths --path bar &&

		git log --oneline >changes &&
		test_line_count = 204 changes &&

		# If a commit we reference is rewritten, we expect the
		# reference to be rewritten.
		name=$(git rev-parse HEAD~203) &&
		echo "Commit referencing ${name:0:8}" >expect &&
		git log --no-walk --format=%s HEAD~202 >actual &&
		test_cmp expect actual &&

		# If a commit we reference was pruned, then the reference
		# has nothing to be rewritten to.  Verify that the commit
		# ID it points to does not exist.
		latest=$(git log --no-walk | grep reverts | awk "{print \$4}" | tr -d '.') &&
		test -n "$latest" &&
		test_must_fail git cat-file -e "$latest"
	)
'

test_expect_success 'commit hash unchanged if requested' '
	(
		git clone file://"$(pwd)"/commit_msg commit_msg_clone_2 &&
		cd commit_msg_clone_2 &&

		name=$(git rev-parse HEAD~204) &&
		git filter-repo --invert-paths --path bar --preserve-commit-hashes &&

		git log --oneline >changes &&
		test_line_count = 204 changes &&

		echo "Commit referencing ${name:0:8}" >expect &&
		git log --no-walk --format=%s HEAD~202 >actual &&
		test_cmp expect actual
	)
'

test_expect_success 'commit message encoding preserved if requested' '
	(
		git init commit_message_encoding &&
		cd commit_message_encoding &&

		cat >input <<-\EOF &&
		feature done
		commit refs/heads/develop
		mark :1
		original-oid deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
		author Just Me <just@here.org> 1234567890 -0200
		committer Just Me <just@here.org> 1234567890 -0200
		encoding iso-8859-7
		data 5
		EOF

		printf "Pi: \360\n\ndone\n" >>input &&

		cat input | git fast-import --quiet &&
		git rev-parse develop >expect &&

		git filter-repo --preserve-commit-encoding --force &&
		git rev-parse develop >actual &&
		test_cmp expect actual
	)
'

test_expect_success 'commit message rewrite unsuccessful' '
	(
		git init commit_msg_not_found &&
		cd commit_msg_not_found &&

		cat >input <<-\EOF &&
		feature done
		commit refs/heads/develop
		mark :1
		original-oid deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
		author Just Me <just@here.org> 1234567890 -0200
		committer Just Me <just@here.org> 1234567890 -0200
		data 2
		A

		commit refs/heads/develop
		mark :2
		original-oid deadbeefcafedeadbeefcafedeadbeefcafecafe
		author Just Me <just@here.org> 1234567890 -0200
		committer Just Me <just@here.org> 1234567890 -0200
		data 2
		B

		commit refs/heads/develop
		mark :3
		original-oid 0000000000000000000000000000000000000004
		author Just Me <just@here.org> 3980014290 -0200
		committer Just Me <just@here.org> 3980014290 -0200
		data 93
		Four score and seven years ago, commit deadbeef ("B",
		2009-02-13) messed up.  This fixes it.
		done
		EOF

		cat input | git filter-repo --stdin --path salutation --force &&

		git log --oneline develop >changes &&
		test_line_count = 3 changes &&

		git log develop >out &&
		grep deadbeef out
	)
'

test_expect_success 'startup sanity checks' '
	(
		git clone file://"$(pwd)"/analyze_me startup_sanity_checks &&
		cd startup_sanity_checks &&

		echo foobar | git hash-object -w --stdin &&
		test_must_fail git filter-repo --path numbers 2>err &&
		test_i18ngrep "expected freshly packed repo" err &&
		git prune &&

		git remote add another_remote /dev/null &&
		test_must_fail git filter-repo --path numbers 2>err &&
		test_i18ngrep "expected one remote, origin" err &&
		git remote rm another_remote &&

		git remote rename origin another_remote &&
		test_must_fail git filter-repo --path numbers 2>err &&
		test_i18ngrep "expected one remote, origin" err &&
		git remote rename another_remote origin &&

		cd words &&
		test_must_fail git filter-repo --path numbers 2>err &&
		test_i18ngrep "GIT_DIR must be .git" err &&
		rm err &&
		cd .. &&

		git config core.bare true &&
		test_must_fail git filter-repo --path numbers 2>err &&
		test_i18ngrep "GIT_DIR must be ." err &&
		git config core.bare false &&

		git update-ref -m "Just Testing" refs/heads/master HEAD &&
		test_must_fail git filter-repo --path numbers 2>err &&
		test_i18ngrep "expected at most one entry in the reflog" err &&
		git reflog expire --expire=now &&

		echo yes >>words/know &&
		git stash save random change &&
		rm -rf .git/logs/ &&
		git gc &&
		test_must_fail git filter-repo --path numbers 2>err &&
		test_i18ngrep "has stashed changes" err &&
		git update-ref -d refs/stash &&

		echo yes >>words/know &&
		git add words/know &&
		git gc --prune=now &&
		test_must_fail git filter-repo --path numbers 2>err &&
		test_i18ngrep "you have uncommitted changes" err &&
		git checkout HEAD words/know &&

		echo yes >>words/know &&
		test_must_fail git filter-repo --path numbers 2>err &&
		test_i18ngrep "you have unstaged changes" err &&
		git checkout -- words/know &&

		test_must_fail git filter-repo --path numbers 2>err &&
		test_i18ngrep "you have untracked changes" err &&
		rm err &&

		git worktree add ../other-worktree HEAD &&
		test_must_fail git filter-repo --path numbers 2>../err &&
		test_i18ngrep "you have multiple worktrees" ../err &&
		rm -rf ../err &&
		git worktree remove ../other-worktree &&

		git update-ref -d refs/remotes/origin/master &&
		test_must_fail git filter-repo --path numbers 2>../err &&
		test_i18ngrep "refs/heads/master exists, but refs/remotes/origin/master not found" ../err &&
		git update-ref -m restoring refs/remotes/origin/master refs/heads/master &&
		rm ../err &&

		rm .git/logs/refs/remotes/origin/master &&
		git update-ref -m funsies refs/remotes/origin/master refs/heads/master~1 &&
		test_must_fail git filter-repo --path numbers 2>../err &&
		test_i18ngrep "refs/heads/master does not match refs/remotes/origin/master" ../err &&
		rm ../err
	)
'

test_expect_success 'other startup error cases and requests for help' '
	(
		git init startup_errors &&
		cd startup_errors &&

		git filter-repo -h >out &&
		test_i18ngrep "filter-repo destructively rewrites history" out &&

		test_must_fail git filter-repo 2>err &&
		test_i18ngrep "No arguments specified." err &&

		test_must_fail git filter-repo --analyze 2>err &&
		test_i18ngrep "Nothing to analyze; repository is empty" err &&

		(
			GIT_CEILING_DIRECTORIES=$(pwd) &&
			export GIT_CEILING_DIRECTORIES &&
			mkdir not_a_repo &&
			cd not_a_repo &&
			test_must_fail git filter-repo --dry-run 2>err &&
			test_i18ngrep "returned non-zero exit status" err &&
			rm err &&
			cd .. &&
			rmdir not_a_repo
		) &&

		test_must_fail git filter-repo --analyze --path foobar 2>err &&
		test_i18ngrep ": --analyze is incompatible with --path" err &&

		test_must_fail git filter-repo --analyze --stdin 2>err &&
		test_i18ngrep ": --analyze is incompatible with --stdin" err &&

		test_must_fail git filter-repo --path-rename foo:bar --use-base-name 2>err &&
		test_i18ngrep ": --use-base-name and --path-rename are incompatible" err &&

		test_must_fail git filter-repo --path-rename foo:bar/ 2>err &&
		test_i18ngrep "either ends with a slash then both must." err &&

		test_must_fail git filter-repo --paths-from-file <(echo "foo==>bar/") 2>err &&
		test_i18ngrep "either ends with a slash then both must." err &&

		test_must_fail git filter-repo --paths-from-file <(echo "glob:*.py==>newname") 2>err &&
		test_i18ngrep "renaming globs makes no sense" err &&

		test_must_fail git filter-repo --strip-blobs-bigger-than 3GiB 2>err &&
		test_i18ngrep "could not parse.*3GiB" err &&

		test_must_fail git filter-repo --path-rename foo/bar:. 2>err &&
		test_i18ngrep "Invalid path component .\.. found in .foo/bar:\." err

	)
'

test_expect_success 'invalid fast-import directives' '
	(
		git init invalid_directives &&
		cd invalid_directives &&

		echo "get-mark :15" | \
			test_must_fail git filter-repo --stdin --force 2>err &&
		test_i18ngrep "Unsupported command" err &&

		echo "invalid-directive" | \
			test_must_fail git filter-repo --stdin --force 2>err &&
		test_i18ngrep "Could not parse line" err
	)
'

test_expect_success 'mailmap sanity checks' '
	(
		git clone file://"$(pwd)"/analyze_me mailmap_sanity_checks &&
		cd mailmap_sanity_checks &&

		test_must_fail git filter-repo --mailmap /fake/path 2>../err &&
		test_i18ngrep "Cannot read /fake/path" ../err &&

		echo "Total Bogus" >../whoopsies &&
		test_must_fail git filter-repo --mailmap ../whoopsies 2>../err &&
		test_i18ngrep "Unparseable mailmap file" ../err &&
		rm ../err &&
		rm ../whoopsies &&

		echo "Me <me@site.com> Myself <yo@email.com> Extraneous" >../whoopsies &&
		test_must_fail git filter-repo --mailmap ../whoopsies 2>../err &&
		test_i18ngrep "Unparseable mailmap file" ../err &&
		rm ../err &&
		rm ../whoopsies
	)
'

test_expect_success 'incremental import' '
	(
		git clone file://"$(pwd)"/analyze_me incremental &&
		cd incremental &&

		original=$(git rev-parse master) &&
		git fast-export --reference-excluded-parents master~2..master \
			| git filter-repo --stdin --refname-callback "return b\"develop\"" &&
		test "$(git rev-parse develop)" = "$original"
	)
'

test_expect_success '--target' '
	git init target &&
	(
		cd target &&
		git checkout -b other &&
		echo hello >world &&
		git add world &&
		git commit -m init &&
		git checkout -b unique
	) &&
	git -C target rev-parse unique >target/expect &&
	git filter-repo --source analyze_me --target target --path fake_submodule --force --debug &&
	test 2 = $(git -C target rev-list --count master) &&
	test_must_fail git -C target rev-parse other &&
	git -C target rev-parse unique >target/actual &&
	test_cmp target/expect target/actual
'

test_expect_success '--refs' '
	git init refs &&
	(
		cd refs &&
		git checkout -b other &&
		echo hello >world &&
		git add world &&
		git commit -m init
	) &&
	git -C refs rev-parse other >refs/expect &&
	git -C analyze_me rev-parse master >refs/expect &&
	git filter-repo --source analyze_me --target refs --refs master --force &&
	git -C refs rev-parse other >refs/actual &&
	git -C refs rev-parse master >refs/actual &&
	test_cmp refs/expect refs/actual
'

test_expect_success 'reset to specific refs' '
	test_create_repo reset_to_specific_refs &&
	(
		cd reset_to_specific_refs &&

		git commit --allow-empty -m initial &&
		INITIAL=$(git rev-parse HEAD) &&
		echo "$INITIAL refs/heads/develop" >expect &&

		cat >input <<-INPUT_END &&
		reset refs/heads/develop
		from $INITIAL

		reset refs/heads/master
		from 0000000000000000000000000000000000000000
		INPUT_END

		cat input | git filter-repo --force --stdin &&
		git show-ref >actual &&
		test_cmp expect actual
	)
'

test_expect_success 'setup handle funny characters' '
	test_create_repo funny_chars &&
	(
		cd funny_chars &&

		git symbolic-ref HEAD refs/heads/españa &&

		printf "بتتكلم بالهندي؟\n" >señor &&
		printf "Αυτά μου φαίνονται αλαμπουρνέζικα.\n" >>señor &&
		printf "זה סינית בשבילי\n" >>señor &&
		printf "ちんぷんかんぷん\n" >>señor &&
		printf "За мене тоа е шпанско село\n" >>señor &&
		printf "看起来像天书。\n" >>señor &&
		printf "انگار ژاپنی حرف می زنه\n" >>señor &&
		printf "Это для меня китайская грамота.\n" >>señor &&
		printf "To mi je španska vas\n" >>señor &&
		printf "Konuya Fransız kaldım\n" >>señor &&
		printf "עס איז די שפּראַך פון גיבבעריש\n" >>señor &&
		printf "Not even UTF-8:\xe0\x80\x80\x00\n" >>señor &&

		cp señor señora &&
		cp señor señorita &&
		git add . &&

		export GIT_AUTHOR_NAME="Nguyễn Arnfjörð Gábor" &&
		export GIT_COMMITTER_NAME=$GIT_AUTHOR_NAME &&
		export GIT_AUTHOR_EMAIL="emails@are.ascii" &&
		export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL" &&
		git commit -m "€$£₽₪" &&

		git tag -a -m "₪₽£€$" סְפָרַד
	)
'

test_expect_success 'handle funny characters' '
	(
		git clone file://"$(pwd)"/funny_chars funny_chars_checks &&
		cd funny_chars_checks &&

		file_sha=$(git rev-parse :0:señor) &&
		former_head_sha=$(git rev-parse HEAD) &&
		git filter-repo --to-subdirectory-filter títulos &&

		cat <<-EOF >expect &&
		100644 $file_sha 0	"t\303\255tulos/se\303\261or"
		100644 $file_sha 0	"t\303\255tulos/se\303\261ora"
		100644 $file_sha 0	"t\303\255tulos/se\303\261orita"
		EOF

		git ls-files -s >actual &&
		test_cmp expect actual &&

		commit_sha=$(git rev-parse HEAD) &&
		tag_sha=$(git rev-parse סְפָרַד) &&
		cat <<-EOF >expect &&
		$commit_sha refs/heads/españa
		$commit_sha refs/replace/$former_head_sha
		$tag_sha refs/tags/סְפָרַד
		EOF

		git show-ref >actual &&
		test_cmp expect actual &&

		echo "€$£₽₪" >expect &&
		git cat-file -p HEAD | tail -n 1 >actual &&

		echo "₪₽£€$" >expect &&
		git cat-file -p סְפָרַד | tail -n 1 >actual
        )
'

test_expect_success '--state-branch with changing renames' '
	test_create_repo state_branch_renames_export
	test_create_repo state_branch_renames &&
	(
		cd state_branch_renames &&
		git fast-import --quiet <$DATA/basic-numbers &&
		git branch -d A &&
		git branch -d B &&
		git tag -d v1.0 &&

		ORIG=$(git rev-parse master) &&
		git reset --hard master~1 &&
		git filter-repo --path-rename ten:zehn \
                                --state-branch state_info \
                                --target ../state_branch_renames_export &&

		cd ../state_branch_renames_export &&
		git log --format=%s --name-status >actual &&
		cat <<-EOF >expect &&
			Merge branch ${SQ}A${SQ} into B
			add twenty

			M	twenty
			add ten

			M	zehn
			Initial

			A	twenty
			A	zehn
			EOF
		test_cmp expect actual &&

		cd ../state_branch_renames &&

		git reset --hard $ORIG &&
		git filter-repo --path-rename twenty:veinte \
                                --state-branch state_info \
                                --target ../state_branch_renames_export &&

		cd ../state_branch_renames_export &&
		git log --format=%s --name-status >actual &&
		cat <<-EOF >expect &&
			whatever

			A	ten
			A	veinte
			Merge branch ${SQ}A${SQ} into B
			add twenty

			M	twenty
			add ten

			M	zehn
			Initial

			A	twenty
			A	zehn
			EOF
		test_cmp expect actual
	)
'

test_expect_success '--state-branch with expanding paths and refs' '
	test_create_repo state_branch_more_paths_export
	test_create_repo state_branch_more_paths &&
	(
		cd state_branch_more_paths &&
		git fast-import --quiet <$DATA/basic-numbers &&

		git reset --hard master~1 &&
		git filter-repo --path ten --state-branch state_info \
                                --target ../state_branch_more_paths_export \
                                --refs master &&

		cd ../state_branch_more_paths_export &&
		echo 2 >expect &&
		git rev-list --count master >actual &&
		test_cmp expect actual &&
		test_must_fail git rev-parse master~1:twenty &&
		test_must_fail git rev-parse master:twenty &&

		cd ../state_branch_more_paths &&

		git reset --hard v1.0 &&
		git filter-repo --path ten --path twenty \
                                --state-branch state_info \
                                --target ../state_branch_more_paths_export &&

		cd ../state_branch_more_paths_export &&
		echo 3 >expect &&
		git rev-list --count master >actual &&
		test_cmp expect actual &&
		test_must_fail git rev-parse master~2:twenty &&
		git rev-parse master:twenty
	)
'

test_expect_success 'degenerate merge with non-matching filenames' '
	test_create_repo degenerate_merge_differing_filenames &&
	(
		cd degenerate_merge_differing_filenames &&

		touch "foo \"quote\" bar" &&
		git add "foo \"quote\" bar" &&
		git commit -m "Add foo \"quote\" bar"
		git branch A &&

		git checkout --orphan B &&
		git reset --hard &&
		mkdir -p pkg/list &&
		test_commit pkg/list/whatever &&
		test_commit unwanted_file &&

		git checkout A &&
		git merge --allow-unrelated-histories --no-commit B &&
		>pkg/list/wanted &&
		git add pkg/list/wanted &&
		git rm -f pkg/list/whatever.t &&
		git commit &&

		git filter-repo --force --path pkg/list &&
		! test_path_is_file pkg/list/whatever.t &&
		git ls-files >actual
		echo pkg/list/wanted >expect &&
		test_cmp expect actual
	)
'

test_expect_success 'tweaking just a tag' '
	test_create_repo tweaking_just_a_tag &&
	(
		cd tweaking_just_a_tag &&

		test_commit foo &&
		git tag -a -m "Here is a tag" mytag &&

		git filter-repo --force --refs mytag ^mytag^{commit} --name-callback "return name.replace(b\"Mitter\", b\"L D\")" &&

		git cat-file -p mytag | grep C.O.L.D
	)
'

test_expect_success '--version' '
	git filter-repo --version >actual &&
	git hash-object ../../git-filter-repo | colrm 13 >expect &&
	test_cmp expect actual
'

test_done
