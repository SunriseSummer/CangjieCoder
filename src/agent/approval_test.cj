package cangjiecoder.agent

import std.unittest.*
import std.unittest.testmacro.*
import cangjiecoder.tools.*

@Test
class ApprovalPolicyNameTests {
    @TestCase
    func names() {
        @Expect(approvalPolicyName(Auto), "auto")
        @Expect(approvalPolicyName(Default_), "default")
        @Expect(approvalPolicyName(ReadOnly), "readonly")
    }
}

@Test
class ParseApprovalPolicyTests {
    @TestCase
    func canonicalSpellings() {
        @Expect(parseApprovalPolicy("auto").isSome(), true)
        @Expect(parseApprovalPolicy("default").isSome(), true)
        @Expect(parseApprovalPolicy("readonly").isSome(), true)
    }

    @TestCase
    func aliases() {
        // 别名
        @Expect(parseApprovalPolicy("yolo").isSome(), true)   // → auto
        @Expect(parseApprovalPolicy("normal").isSome(), true) // → default
        @Expect(parseApprovalPolicy("ro").isSome(), true)     // → readonly
        @Expect(parseApprovalPolicy("read").isSome(), true)   // → readonly
    }

    @TestCase
    func caseInsensitive() {
        @Expect(parseApprovalPolicy("AUTO").isSome(), true)
        @Expect(parseApprovalPolicy("ReadOnly").isSome(), true)
    }

    @TestCase
    func returnsNoneForUnknown() {
        @Expect(parseApprovalPolicy("nonsense").isNone(), true)
        @Expect(parseApprovalPolicy("").isNone(), true)
    }

    @TestCase
    func roundtripWithName() {
        // parse(name(p)) 应得到等价策略
        for (policy in [Auto, Default_, ReadOnly]) {
            let name = approvalPolicyName(policy)
            @Expect(parseApprovalPolicy(name).isSome(), true)
        }
    }
}

@Test
class ApproverBehaviorTests {
    @TestCase
    func safeToolsAlwaysApproved() {
        for (policy in [Auto, Default_, ReadOnly]) {
            let approver = Approver(policy)
            let (ok, _) = approver.confirm("any", "{}", Safe)
            @Expect(ok, true)
        }
    }

    @TestCase
    func autoApprovesSensitiveTools() {
        let approver = Approver(Auto)
        let (ok, switched) = approver.confirm("run_bash", "{}", Sensitive)
        @Expect(ok, true)
        @Expect(switched, false)
    }

    @TestCase
    func readOnlyRejectsSensitiveTools() {
        let approver = Approver(ReadOnly)
        let (ok, _) = approver.confirm("edit_file", "{}", Sensitive)
        @Expect(ok, false)
    }

    // Default_ 模式会调用 readln 阻塞读取，不适合在自动化测试中触发，
    // 这里只验证策略字段可以被改变，相当于 /approve 切换的行为
    @TestCase
    func policyMutationIsObservable() {
        let approver = Approver(Default_)
        @Expect(approvalPolicyName(approver.policy), "default")
        approver.policy = Auto
        @Expect(approvalPolicyName(approver.policy), "auto")
        let (ok, _) = approver.confirm("run_bash", "{}", Sensitive)
        @Expect(ok, true)
    }
}
