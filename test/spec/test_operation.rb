require 'orogen/test'

describe Orocos::Spec::ConfigurationObject do
    include Orocos::Generation::Test

    describe "#to_h" do
        attr_reader :task, :op
        before do
            @task = Orocos::Spec::TaskContext.new(Orocos::Generation::Project.new)
            @op = task.operation('op')
        end

        it "marshals the name" do
            assert_equal 'op', op.to_h[:name]
        end
        it "marshals empty documentation as an empty string" do
            op.doc ""
            assert_equal "", op.to_h[:doc]
        end
        it "marshals the documentation" do
            op.doc "with documentation"
            assert_equal "with documentation", op.to_h[:doc]
        end
        it "does not add a return field if the operation returns nothing" do
            assert !op.to_h.has_key?(:returns)
        end
        it "marshals the typelib return type if the operation returns a value" do
            op.returns("/double")
            double_t = task.project.find_type('/double')
            assert_equal double_t.to_h,
                op.to_h[:returns][:type]
        end
        it "sets an empty return type documentation if none is specified" do
            op.returns("/double")
            assert_equal "", op.to_h[:returns][:doc]
        end
        it "sets the return type documentation field to the provided documentation" do
            op.returns("/double", "return type description")
            assert_equal "return type description", op.to_h[:returns][:doc]
        end
        it "sets the arguments field to an empty array if there are none" do
            assert_equal [], op.to_h[:arguments]
        end
        it "marshals its arguments" do
            op.argument('arg', '/double')
            double_t = task.project.find_type('/double')
            assert_equal [Hash[name: 'arg', type: double_t.to_h, doc: ""]], op.to_h[:arguments]
        end
        it "marshals its arguments documentation" do
            op.argument('arg', '/double', 'arg documentation')
            double_t = task.project.find_type('/double')
            assert_equal [Hash[name: 'arg', type: double_t.to_h, doc: "arg documentation"]], op.to_h[:arguments]
        end
    end
end

