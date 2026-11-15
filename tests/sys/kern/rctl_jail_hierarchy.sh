#
# SPDX-License-Identifier: BSD-2-Clause
#
# Copyright (c) 2026 PePe Amengual
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

# rctl rules on a jail apply to the processes of its child jails too.

PARENT=rctl_hier_parent
CHILD=${PARENT}.child

require_racct()
{
	if [ "$(sysctl -n kern.racct.enable 2>/dev/null)" != "1" ]; then
		atf_skip "RACCT is not enabled (kern.racct.enable=1 in loader.conf)"
	fi
}

make_jails()
{
	jail -c name=${PARENT} path=/ children.max=1 persist ||
	    atf_fail "creating ${PARENT}"
	jail -c name=${CHILD} path=/ persist || atf_fail "creating ${CHILD}"
}

remove_jails()
{
	rctl -r jail:${CHILD} >/dev/null 2>&1
	rctl -r jail:${PARENT} >/dev/null 2>&1
	jail -r ${CHILD} >/dev/null 2>&1
	jail -r ${PARENT} >/dev/null 2>&1
	true
}

atf_test_case "feature"
feature_head()
{
	atf_set descr 'kern.features.rctl_jail_hierarchy is advertised'
}
feature_body()
{
	atf_check -o inline:"1\n" sysctl -n kern.features.rctl_jail_hierarchy
}

atf_test_case "maxproc_parent_rule" "cleanup"
maxproc_parent_rule_head()
{
	atf_set descr 'A maxproc rule on a jail limits forks in its child jail'
	atf_set require.user root
}
maxproc_parent_rule_body()
{
	require_racct
	make_jails

	# Without a rule, a shell in the child forks freely.
	atf_check -o inline:"a\nb\nc\n" \
	    jexec ${CHILD} sh -c 'echo a | cat; echo b | cat; echo c | cat'

	# The shell is the only process of the parent's hierarchy: with a
	# limit of 1 it can't fork.
	atf_check -o ignore rctl -a jail:${PARENT}:maxproc:deny=1
	atf_check -s not-exit:0 -o ignore -e match:"fork" \
	    jexec ${CHILD} sh -c 'echo a | cat; echo b | cat'

	atf_check -o ignore rctl -r jail:${PARENT}:maxproc:deny
	atf_check -o inline:"a\n" jexec ${CHILD} sh -c 'echo a | cat'
}
maxproc_parent_rule_cleanup()
{
	remove_jails
}

atf_test_case "memoryuse_parent_rule" "cleanup"
memoryuse_parent_rule_head()
{
	atf_set descr 'A memoryuse:sigkill rule on a jail kills processes of its child jail'
	atf_set require.user root
	atf_set timeout 60
}
memoryuse_parent_rule_body()
{
	require_racct
	make_jails

	# 64 MB touched and held for a few seconds (racctd samples RSS once a
	# second) runs fine without a rule ...
	atf_check -o ignore -e ignore \
	    jexec ${CHILD} dd if=/dev/zero of=/dev/null bs=64m count=2000

	# ... and is killed with a 32 MB rule on the parent.
	atf_check -o ignore rctl -a jail:${PARENT}:memoryuse:sigkill=32m
	atf_check -s signal:kill -o ignore -e ignore \
	    jexec ${CHILD} dd if=/dev/zero of=/dev/null bs=64m count=2000
}
memoryuse_parent_rule_cleanup()
{
	remove_jails
}

atf_init_test_cases()
{
	atf_add_test_case feature
	atf_add_test_case maxproc_parent_rule
	atf_add_test_case memoryuse_parent_rule
}
