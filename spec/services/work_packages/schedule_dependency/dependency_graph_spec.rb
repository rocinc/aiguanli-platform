# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkPackages::ScheduleDependency::DependencyGraph do
  create_shared_association_defaults_for_work_package_factory

  describe "#depends_on?" do
    context "with simple linear predecessor/successor dependencies" do
      # create a linear dependency: wp1 -> wp2 -> wp3
      let_work_packages(<<~TABLE)
        hierarchy | scheduling mode | successors
        wp1       | manual          | wp2
        wp2       | automatic       | wp3
        wp3       | automatic       |
      TABLE

      let(:schedule_dependency) { WorkPackages::ScheduleDependency.new([wp1]) }
      let(:wp1_dependency) { WorkPackages::ScheduleDependency::Dependency.new(wp1, schedule_dependency) }
      let(:wp2_dependency) { WorkPackages::ScheduleDependency::Dependency.new(wp2, schedule_dependency) }
      let(:wp3_dependency) { WorkPackages::ScheduleDependency::Dependency.new(wp3, schedule_dependency) }
      let(:dependencies) { [wp1_dependency, wp2_dependency, wp3_dependency] }

      it "returns true when a given work package depends on the work package from the given dependency" do
        dependency_graph = described_class.new(dependencies)

        expect(dependency_graph.depends_on?(wp1, wp1_dependency)).to be(false)
        expect(dependency_graph.depends_on?(wp1, wp2_dependency)).to be(false)
        expect(dependency_graph.depends_on?(wp1, wp3_dependency)).to be(false)

        expect(dependency_graph.depends_on?(wp2, wp1_dependency)).to be(true)
        expect(dependency_graph.depends_on?(wp2, wp2_dependency)).to be(false)
        expect(dependency_graph.depends_on?(wp2, wp3_dependency)).to be(false)

        expect(dependency_graph.depends_on?(wp3, wp1_dependency)).to be(true)
        expect(dependency_graph.depends_on?(wp3, wp2_dependency)).to be(true)
        expect(dependency_graph.depends_on?(wp3, wp3_dependency)).to be(false)
      end
    end

    context "with circular dependencies between two work packages" do
      # Create circular dependency: wp1 -> wp2 -> wp1
      let_work_packages(<<~TABLE)
        subject | scheduling mode | successors
        wp1     | automatic       | wp2
        wp2     | automatic       | wp1
      TABLE

      let(:schedule_dependency) { WorkPackages::ScheduleDependency.new([wp1]) }
      let(:wp1_dependency) { WorkPackages::ScheduleDependency::Dependency.new(wp1, schedule_dependency) }
      let(:wp2_dependency) { WorkPackages::ScheduleDependency::Dependency.new(wp2, schedule_dependency) }
      let(:dependencies) { [wp1_dependency, wp2_dependency] }

      it "avoids infinite recursion and returns true when given a dependent dependency" do
        dependency_graph = described_class.new(dependencies)

        expect(dependency_graph.depends_on?(wp1, wp1_dependency)).to be(false)
        expect(dependency_graph.depends_on?(wp1, wp2_dependency)).to be(true)

        expect(dependency_graph.depends_on?(wp2, wp1_dependency)).to be(true)
        expect(dependency_graph.depends_on?(wp2, wp2_dependency)).to be(false)
      end
    end

    context "with circular dependency between one work package" do
      # Create circular dependency: wp1 -> wp2 -> wp1
      let_work_packages(<<~TABLE)
        subject | scheduling mode | successors
        wp1     | automatic       | wp1
      TABLE

      let(:schedule_dependency) { WorkPackages::ScheduleDependency.new([wp1]) }
      let(:wp1_dependency) { WorkPackages::ScheduleDependency::Dependency.new(wp1, schedule_dependency) }
      let(:dependencies) { [wp1_dependency] }

      it "avoids infinite recursion and returns false when given itsef as a dependency" do
        dependency_graph = described_class.new(dependencies)

        expect(dependency_graph.depends_on?(wp1, wp1_dependency)).to be(false)
      end
    end
  end
end
