# Changelog

## [0.6.1](https://github.com/joshrotenberg/git_wrapper_ex/compare/v0.6.0...v0.6.1) (2026-07-10)


### Bug Fixes

* **forcola:** build stdout accumulator as a proper list ([#159](https://github.com/joshrotenberg/git_wrapper_ex/issues/159)) ([2505416](https://github.com/joshrotenberg/git_wrapper_ex/commit/250541684c7ca312b4eb4205ab98ad8c0dff4939))
* **test:** stop GitTest reusing polluted temp repos across runs ([#158](https://github.com/joshrotenberg/git_wrapper_ex/issues/158)) ([891ccc6](https://github.com/joshrotenberg/git_wrapper_ex/commit/891ccc6ac0b4747dbd8434bbb88355f8d54c1f6b))

## [0.6.0](https://github.com/joshrotenberg/git_wrapper_ex/compare/v0.5.0...v0.6.0) (2026-07-10)


### Features

* add a stdin input channel to Git.Runner ([#154](https://github.com/joshrotenberg/git_wrapper_ex/issues/154)) ([8b382bf](https://github.com/joshrotenberg/git_wrapper_ex/commit/8b382bf09b3c5cc97a55672bdca84094f3d05d52)), closes [#93](https://github.com/joshrotenberg/git_wrapper_ex/issues/93)
* add apply --numstat and am --keep-cr flags ([#139](https://github.com/joshrotenberg/git_wrapper_ex/issues/139)) ([174bde4](https://github.com/joshrotenberg/git_wrapper_ex/commit/174bde4cea8c6c48cb7db4cae4d28f9e0906719e)), closes [#99](https://github.com/joshrotenberg/git_wrapper_ex/issues/99)
* add conflict stage inspection and resolution helpers ([#144](https://github.com/joshrotenberg/git_wrapper_ex/issues/144)) ([d640493](https://github.com/joshrotenberg/git_wrapper_ex/commit/d64049373d314cad674fbeca88029297f1cc9d1a))
* add diff options and numstat parsing to Git.diff ([#133](https://github.com/joshrotenberg/git_wrapper_ex/issues/133)) ([bdd4960](https://github.com/joshrotenberg/git_wrapper_ex/commit/bdd4960ef0fce7c22a61c677feb240e3ba47563c)), closes [#94](https://github.com/joshrotenberg/git_wrapper_ex/issues/94)
* add follow-tags, push-option, signed, and lease-ref to push ([#128](https://github.com/joshrotenberg/git_wrapper_ex/issues/128)) ([fd47762](https://github.com/joshrotenberg/git_wrapper_ex/commit/fd477620e4aca796b33a035151009cafedea9175)), closes [#101](https://github.com/joshrotenberg/git_wrapper_ex/issues/101)
* add Git.Branches.delete_squashed for squash-merged branch cleanup ([#151](https://github.com/joshrotenberg/git_wrapper_ex/issues/151)) ([5d01657](https://github.com/joshrotenberg/git_wrapper_ex/commit/5d016573baa0071d644347227f059aa59010970b)), closes [#114](https://github.com/joshrotenberg/git_wrapper_ex/issues/114)
* add history-control options to Git.log (--follow, --no-merges, --first-parent, grep modifiers, ref selectors) ([#134](https://github.com/joshrotenberg/git_wrapper_ex/issues/134)) ([46df3be](https://github.com/joshrotenberg/git_wrapper_ex/commit/46df3be40adb073868d32b9030f8ec74730e4cee))
* add merge strategies, --ff-only, and --continue/--quit to Git.merge ([#126](https://github.com/joshrotenberg/git_wrapper_ex/issues/126)) ([6e8f000](https://github.com/joshrotenberg/git_wrapper_ex/commit/6e8f0008668fb6d271a0ba00b69d86bf97eb2ad7))
* add metadata and hook flags to Git.commit, make message optional ([#125](https://github.com/joshrotenberg/git_wrapper_ex/issues/125)) ([b4bacad](https://github.com/joshrotenberg/git_wrapper_ex/commit/b4bacad1565edef6f588940fd93c6e0fecfc3738)), closes [#89](https://github.com/joshrotenberg/git_wrapper_ex/issues/89)
* add option coverage to git status ([#131](https://github.com/joshrotenberg/git_wrapper_ex/issues/131)) ([a3b80eb](https://github.com/joshrotenberg/git_wrapper_ex/commit/a3b80ebc214754fdeb5f7804d9672aa533a7a42e)), closes [#100](https://github.com/joshrotenberg/git_wrapper_ex/issues/100)
* add pathspec form to Git.reset (unstage a single file) ([#123](https://github.com/joshrotenberg/git_wrapper_ex/issues/123)) ([53c9ab8](https://github.com/joshrotenberg/git_wrapper_ex/commit/53c9ab8d4f0bcc8e573dc34814574c26c236e911)), closes [#88](https://github.com/joshrotenberg/git_wrapper_ex/issues/88)
* add raw diff plumbing (diff-tree, diff-index, diff-files) ([#143](https://github.com/joshrotenberg/git_wrapper_ex/issues/143)) ([6412dfc](https://github.com/joshrotenberg/git_wrapper_ex/commit/6412dfc7c0892dfe3b020419d7d0d2857f1abf4d))
* add rebase exec, update-refs, strategy, root, empty, and quit options ([#130](https://github.com/joshrotenberg/git_wrapper_ex/issues/130)) ([e5c33a4](https://github.com/joshrotenberg/git_wrapper_ex/commit/e5c33a40ced015bbce155464bb9af925030a6996)), closes [#103](https://github.com/joshrotenberg/git_wrapper_ex/issues/103)
* add refspec support to Git.fetch and Git.push ([#132](https://github.com/joshrotenberg/git_wrapper_ex/issues/132)) ([bc531e7](https://github.com/joshrotenberg/git_wrapper_ex/commit/bc531e7805c825d2a0de1d443749f1cc5cb23e48)), closes [#104](https://github.com/joshrotenberg/git_wrapper_ex/issues/104)
* add release/sync and safe-integration workflows ([#155](https://github.com/joshrotenberg/git_wrapper_ex/issues/155)) ([0bc3868](https://github.com/joshrotenberg/git_wrapper_ex/commit/0bc3868798358961128f98791cedc854de2cfc7b)), closes [#116](https://github.com/joshrotenberg/git_wrapper_ex/issues/116) [#117](https://github.com/joshrotenberg/git_wrapper_ex/issues/117)
* add remote-aware branch cleanup (prune_gone, delete_branch) ([#147](https://github.com/joshrotenberg/git_wrapper_ex/issues/147)) ([a12b62b](https://github.com/joshrotenberg/git_wrapper_ex/commit/a12b62b9f02b2f3ae14e50750806dd6783784361))
* add resolve, abort, and continue workflows to Git.Conflicts ([#150](https://github.com/joshrotenberg/git_wrapper_ex/issues/150)) ([c6a5d11](https://github.com/joshrotenberg/git_wrapper_ex/commit/c6a5d113abb40770721970bc1ee8fa37933391ca)), closes [#115](https://github.com/joshrotenberg/git_wrapper_ex/issues/115)
* add scaling options to Git.clone (--filter, --sparse, --bare, --mirror, ...) ([#127](https://github.com/joshrotenberg/git_wrapper_ex/issues/127)) ([8c417e3](https://github.com/joshrotenberg/git_wrapper_ex/commit/8c417e3fbba40468c359b602acdb0b680fa9914b)), closes [#97](https://github.com/joshrotenberg/git_wrapper_ex/issues/97)
* add signing across commit, tag, and merge ([#153](https://github.com/joshrotenberg/git_wrapper_ex/issues/153)) ([181370a](https://github.com/joshrotenberg/git_wrapper_ex/commit/181370ae0dd67be1dddb9fe630c8ed88ed01bfa2)), closes [#105](https://github.com/joshrotenberg/git_wrapper_ex/issues/105)
* add start-point to branch creation ([#138](https://github.com/joshrotenberg/git_wrapper_ex/issues/138)) ([d2cea36](https://github.com/joshrotenberg/git_wrapper_ex/commit/d2cea368322dce20bab6252ad1045eec98f7cb06)), closes [#90](https://github.com/joshrotenberg/git_wrapper_ex/issues/90)
* add stash apply, clear, branch, show, and keep-index ([#137](https://github.com/joshrotenberg/git_wrapper_ex/issues/137)) ([3c90153](https://github.com/joshrotenberg/git_wrapper_ex/commit/3c90153dc069f2c3041dd79f7626aaa58915cd09)), closes [#98](https://github.com/joshrotenberg/git_wrapper_ex/issues/98)
* add tag force, message file, and listing filter options ([#129](https://github.com/joshrotenberg/git_wrapper_ex/issues/129)) ([335d918](https://github.com/joshrotenberg/git_wrapper_ex/commit/335d918baa1adc7175c46dae27a8aab6a5610154)), closes [#102](https://github.com/joshrotenberg/git_wrapper_ex/issues/102)
* add undo-family workflows (undo_last_commit, squash_last, discard_all) ([#142](https://github.com/joshrotenberg/git_wrapper_ex/issues/142)) ([17e5581](https://github.com/joshrotenberg/git_wrapper_ex/commit/17e558105e919f177a26202d6384f688b149aeca))
* add user-defined workflow combinators (chain/2, with_branch/3, with_stash/2) ([#148](https://github.com/joshrotenberg/git_wrapper_ex/issues/148)) ([ebd7aad](https://github.com/joshrotenberg/git_wrapper_ex/commit/ebd7aad47af5e7e4d1c655e7899e8303182679b6)), closes [#118](https://github.com/joshrotenberg/git_wrapper_ex/issues/118)
* add version, count-objects, var, name-rev, and check-ref-format helpers ([#145](https://github.com/joshrotenberg/git_wrapper_ex/issues/145)) ([55a1577](https://github.com/joshrotenberg/git_wrapper_ex/commit/55a1577c8d3481ff9733a16ca0f3d3759c36402e)), closes [#111](https://github.com/joshrotenberg/git_wrapper_ex/issues/111)
* adopt forcola for leak-free git execution ([#81](https://github.com/joshrotenberg/git_wrapper_ex/issues/81)) ([ec7a162](https://github.com/joshrotenberg/git_wrapper_ex/commit/ec7a1629f0617f464c6b121f63ec4103b961aaf6)), closes [#80](https://github.com/joshrotenberg/git_wrapper_ex/issues/80)
* compose flags with pathspec in Git.add (-u, -f, -n, -N, --chmod, --renormalize) ([#124](https://github.com/joshrotenberg/git_wrapper_ex/issues/124)) ([310c1e9](https://github.com/joshrotenberg/git_wrapper_ex/commit/310c1e99d423c4ef046b56150e78c67738d4ef2f)), closes [#86](https://github.com/joshrotenberg/git_wrapper_ex/issues/86)
* default GIT_TERMINAL_PROMPT=0 so auth-required git cannot hang ([#120](https://github.com/joshrotenberg/git_wrapper_ex/issues/120)) ([f1e828d](https://github.com/joshrotenberg/git_wrapper_ex/commit/f1e828d474ce669047772fbcb574e8b78a8437ed)), closes [#84](https://github.com/joshrotenberg/git_wrapper_ex/issues/84)
* global -c &lt;key&gt;=&lt;value&gt; config passthrough via base_args ([#122](https://github.com/joshrotenberg/git_wrapper_ex/issues/122)) ([24ef2e8](https://github.com/joshrotenberg/git_wrapper_ex/commit/24ef2e8dfe9e254ace677f7d61c0ff721da35a0d)), closes [#91](https://github.com/joshrotenberg/git_wrapper_ex/issues/91)
* index-manipulation plumbing (read-tree, update-index, mktree) ([#156](https://github.com/joshrotenberg/git_wrapper_ex/issues/156)) ([4108a4f](https://github.com/joshrotenberg/git_wrapper_ex/commit/4108a4f6392f4e0f9d257621841e1bd30476525a)), closes [#108](https://github.com/joshrotenberg/git_wrapper_ex/issues/108)
* make forcola the default runner for leak-free execution ([#152](https://github.com/joshrotenberg/git_wrapper_ex/issues/152)) ([f5400e8](https://github.com/joshrotenberg/git_wrapper_ex/commit/f5400e89ed209b10f11787ff4954aeb0d43579c8)), closes [#119](https://github.com/joshrotenberg/git_wrapper_ex/issues/119)
* wrap git check-attr ([#146](https://github.com/joshrotenberg/git_wrapper_ex/issues/146)) ([bd33f8d](https://github.com/joshrotenberg/git_wrapper_ex/commit/bd33f8d9814d40c2049bce954192ed06bd50326e))
* wrap git merge-tree in --write-tree mode ([#141](https://github.com/joshrotenberg/git_wrapper_ex/issues/141)) ([a1853af](https://github.com/joshrotenberg/git_wrapper_ex/commit/a1853af4ec170d8199356cff51a85fcd3138bc65))
* wrap git write-tree ([#140](https://github.com/joshrotenberg/git_wrapper_ex/issues/140)) ([1a56dda](https://github.com/joshrotenberg/git_wrapper_ex/commit/1a56ddab2efb1bfd87e83d4fe64d67087b2c768a))


### Bug Fixes

* sync/1 autostash surfaces pop conflicts and ignores untracked-only trees ([#135](https://github.com/joshrotenberg/git_wrapper_ex/issues/135)) ([d5800ea](https://github.com/joshrotenberg/git_wrapper_ex/commit/d5800ea228a6cb71238a5e3de5cdd0708c509aa1)), closes [#85](https://github.com/joshrotenberg/git_wrapper_ex/issues/85)

## [0.5.0](https://github.com/joshrotenberg/git_wrapper_ex/compare/v0.4.0...v0.5.0) (2026-04-26)


### Features

* add commit-tree plumbing wrapper ([#77](https://github.com/joshrotenberg/git_wrapper_ex/issues/77)) ([7f3a1ac](https://github.com/joshrotenberg/git_wrapper_ex/commit/7f3a1ac5db9f4cbbedb1b2753b7029cc892c050b))

## [0.4.0](https://github.com/joshrotenberg/git_wrapper_ex/compare/v0.3.0...v0.4.0) (2026-04-09)


### Features

* add apply and am commands (patch workflow) ([#72](https://github.com/joshrotenberg/git_wrapper_ex/issues/72)) ([85830bf](https://github.com/joshrotenberg/git_wrapper_ex/commit/85830bf885199f98b4070bc80fa8e54b1bc0b4f4))
* add higher-level modules (Changes, Tags, Remotes, Stashes, Patch, Conflicts) ([#75](https://github.com/joshrotenberg/git_wrapper_ex/issues/75)) ([f8d5242](https://github.com/joshrotenberg/git_wrapper_ex/commit/f8d52427b14d1d1608327eeefd0847f76070e42a))
* add interpret-trailers and maintenance commands ([#74](https://github.com/joshrotenberg/git_wrapper_ex/issues/74)) ([d03079e](https://github.com/joshrotenberg/git_wrapper_ex/commit/d03079eb5e32a7c458dd8125fa78d0c795d4ae2d))
* add plumbing commands (for-each-ref, hash-object, symbolic-ref, update-ref) ([#73](https://github.com/joshrotenberg/git_wrapper_ex/issues/73)) ([415cd6f](https://github.com/joshrotenberg/git_wrapper_ex/commit/415cd6fb3994ca0f35363cf37c6ea38f8531d6f8))
* add switch and restore commands (modern checkout replacements) ([#70](https://github.com/joshrotenberg/git_wrapper_ex/issues/70)) ([a86d462](https://github.com/joshrotenberg/git_wrapper_ex/commit/a86d4624c8555bac9b6497deb22d45684a3f5dc9)), closes [#60](https://github.com/joshrotenberg/git_wrapper_ex/issues/60)

## [0.3.0](https://github.com/joshrotenberg/git_wrapper_ex/compare/v0.2.0...v0.3.0) (2026-04-05)


### Features

* add describe, shortlog, format-patch, archive, ls-remote, ls-tree, submodule ([#55](https://github.com/joshrotenberg/git_wrapper_ex/issues/55)) ([e26c17f](https://github.com/joshrotenberg/git_wrapper_ex/commit/e26c17f3d9bcd3c20fefbffc815590c7bbc993bf))
* add rev-list, merge-base, cherry, cat-file, check-ignore, notes, range-diff, sparse-checkout ([#58](https://github.com/joshrotenberg/git_wrapper_ex/issues/58)) ([e642c36](https://github.com/joshrotenberg/git_wrapper_ex/commit/e642c3673828d6a8e2eb7f562a439f49d9067bea))
* add tier-3 commands, refactor raw System.cmd usage ([#59](https://github.com/joshrotenberg/git_wrapper_ex/issues/59)) ([4de2f5b](https://github.com/joshrotenberg/git_wrapper_ex/commit/4de2f5b992120be1d160ca31620dc9f65e538cda))

## [0.2.0](https://github.com/joshrotenberg/git_wrapper_ex/compare/v0.1.0...v0.2.0) (2026-04-05)


### Features

* add checkout command (board worker built) ([ceb226d](https://github.com/joshrotenberg/git_wrapper_ex/commit/ceb226dfaeaf4371fe581a21a6005825d92868f6))
* add git add and merge commands (parallel board workers) ([6d5894c](https://github.com/joshrotenberg/git_wrapper_ex/commit/6d5894c9ddc11a1dffab15330c80a77f9d24c5bf))
* add init, clone, reset commands (board workers with reset) ([b9a0d33](https://github.com/joshrotenberg/git_wrapper_ex/commit/b9a0d33f8de4fe9d216a8e9d998da4aaef6f403e))
* add tag and stash commands ([f6f0eaa](https://github.com/joshrotenberg/git_wrapper_ex/commit/f6f0eaafae44683d8eb86704effc47b6a8da47a4))
* add Workflow, Changes, Info, Search modules ([#30](https://github.com/joshrotenberg/git_wrapper_ex/issues/30)) ([c193bb5](https://github.com/joshrotenberg/git_wrapper_ex/commit/c193bb5121a69530b5b63a06c4a895a0244a9f4c))
* complete git CLI wrapper — status, log, commit, branch, diff, remote ([98404ea](https://github.com/joshrotenberg/git_wrapper_ex/commit/98404ea45263545bab7b2c6778a38ac259df2ef5))
* expand to 31 commands, rename to Git module, add higher-level abstractions ([77d8a34](https://github.com/joshrotenberg/git_wrapper_ex/commit/77d8a34c5905ee7abdd2cc00c6693a8f19a73ac1))
* expand to 31 commands, rename to Git, add higher-level modules ([0bef119](https://github.com/joshrotenberg/git_wrapper_ex/commit/0bef11951adf8b94331076cca5bc24bb797b9156))
* workshop setup for agent-driven development ([4cecc10](https://github.com/joshrotenberg/git_wrapper_ex/commit/4cecc10b0c4dfc62c1e33346c6b10a0c7c10afd7))


### Bug Fixes

* CI test failures from default branch being master ([ca1dcdb](https://github.com/joshrotenberg/git_wrapper_ex/commit/ca1dcdb9693a7b676f739102464e22cbd969e955))
