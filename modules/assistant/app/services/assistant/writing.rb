# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# See COPYRIGHT and LICENSE files for more details.
#++

module Assistant
  # The editor's writing actions (04 G3): fix, shorten, translate, sort into
  # the type's template, or anything an administrator set up in the platform's
  # text transform actions, run by the same assistant with the same model,
  # budget and usage record. The team's glossary is put in front of every
  # prompt so the words come out as the team says them. The text streams
  # into the platform's run events, which the editor reads as they arrive.
  class Writing
    GLOSSARY_TITLES = %w[术语表 Glossary 词汇表 Terminology].freeze
    GLOSSARY_LIMIT = 4000
    FLUSH_CHARS = 40

    # Ad-hoc writing the editor offers next to the configured actions.
    BUILT_IN = {
      "continue" => "接着文本的结尾往下写，只写新增的内容。原文必须保持原样：不要重复、改动、总结或评论原文，" \
                    "从原文最后一个字之后直接接上。沿用原文的语气、语种和格式，除非另有要求，写一到两段为限。" \
                    "只返回新增的文字，不要前言和解释，不要加引号。",
      "rewrite" => "Rewrite the text to be clearer and more direct. Keep its meaning, facts, numbers, names, language " \
                   "and Markdown structure. Return only the rewritten text.",
      "acceptance" => "Write an acceptance criteria section for the work package described in the text: three to " \
                      "six checkable bullet points, each one something a tester can confirm. Same language as the " \
                      "text. Return only the section, starting with a heading.",
      "glossary" => "Rewrite the text so that it uses the team glossary's terms exactly, replacing their alternatives. " \
                    "Change nothing else. Return only the text.",
      "translate" => "If the text is mostly Chinese, translate it into English; otherwise translate it into " \
                     "Simplified Chinese. Keep names, ids, numbers and Markdown structure. Return only the translation.",
      "write" => "Write what the instruction asks, in the language of the instruction. Return plain text in " \
                 "short paragraphs, without Markdown markers such as **, #, or bullet symbols. Return only the text."
    }.freeze

    # The two ways the editor goes on working with a draft it already has. They are not offered in
    # the menu; the editor asks for them from the draft's own controls.
    REFINEMENT = {
      "revise" => "你在和一位同事一起改一份稿子。下面会给出原始材料和上一稿，系统说明里有原来的任务和这次的修改意见。" \
                  "请按修改意见重写整份上一稿：意见没有涉及的、已经满意的部分尽量原样保留，只改意见涉及的地方；" \
                  "保持上一稿的语种、风格和 Markdown 结构。直接返回完整的新稿，不要前言，不要解释改了什么，" \
                  "不要加引号或代码块围栏，不要评价写稿的人。",
      "refine_selection" => "你在帮一位同事修改稿子里的一小段。下面会给出全文（只作上下文）和需要修改的片段，" \
                            "系统说明里有修改意见。只重写这个片段：你返回的内容会直接替换原来的片段，所以只返回这一段的" \
                            "替换文本，不要返回全文，不要带上片段前后的其他内容，不要前言和解释，不要加引号或代码块围栏。" \
                            "保持全文的语种、语气和 Markdown 格式（片段是列表项就仍是列表项），保留片段两端原有的空白与换行。" \
                            "不要评价写稿的人。"
    }.freeze

    MODES = BUILT_IN.merge(REFINEMENT).freeze

    INSTRUCTION_LABELS = {
      "continue" => "续写的方向与要求（原文仍须原样保留，只写接在后面的新内容）",
      "rewrite" => "改写的要求",
      "translate" => "翻译的目标语言或风格要求",
      "revise" => "这次的修改意见（最重要，优先于其他做法）",
      "refine_selection" => "这一段的修改意见"
    }.freeze

    def self.actions_for(user:, project: nil, type: nil)
      return [] unless Setting.ai_text_transform_actions_enabled? && Assistant::Llm.configured?

      AI::TextTransformAction.active.ordered.includes(:types).select do |action|
        next true if action.everywhere?
        next false unless type

        action.all_work_package_types? || action.types.include?(type)
      end
    end

    def self.start(user:, input:, action: nil, built_in: nil, instruction: nil, project: nil, type: nil,
                   previous: nil, selection: nil, base: nil, task_instruction: nil)
      system = system_prompt(action:, built_in:, instruction:, project:, type:, base:, task_instruction:)
      run = AI::TextTransformRun.create!(user:, action:, system_prompt: system,
                                         input: compose_input(built_in.to_s, input.to_s, previous.to_s, selection.to_s, base.to_s))
      Assistant::WritingJob.perform_later(run.id, project&.id)
      run
    end

    def self.system_prompt(action:, built_in:, instruction:, project:, type:, base: nil, task_instruction: nil)
      mode = built_in.to_s
      parts = [REFINEMENT[mode] || task_prompt(action, mode)]
      if mode == "revise"
        parts << "原来的任务（重写时仍然要完成它）：#{task_prompt(action, base)}"
        parts << "最初的要求：#{task_instruction.to_s.truncate(1000)}" if task_instruction.present?
      end
      parts << "#{INSTRUCTION_LABELS.fetch(mode, '对方的要求')}：#{instruction.to_s.truncate(1000)}" if instruction.present?
      if action&.injects_type_template && type
        variant = project ? project.type_variant(type) : type.default_variant
        template = variant&.default_work_package_description.presence
        parts << "TEMPLATE:\n#{template}" if template
      end
      glossary = glossary_of(project)
      parts << "TEAM GLOSSARY (use these terms exactly as written, never their alternatives):\n#{glossary}" if glossary
      parts.join("\n\n")
    end

    def self.task_prompt(action, built_in)
      action&.prompt || BUILT_IN.fetch(built_in.to_s) { BUILT_IN["write"] }
    end

    # The tail of a document is what a continuation hangs on, so that is what survives the cut.
    def self.compose_input(mode, input, previous, selection, base)
      case mode
      when "revise"
        material = base == "continue" ? input.last(40_000) : input.first(40_000)
        "【原始材料】\n#{material}\n\n【上一稿】\n#{previous.first(40_000)}"
      when "refine_selection"
        "【全文，仅作上下文】\n#{input.first(60_000)}\n\n【需要修改的片段】\n#{selection.first(10_000)}"
      else
        input.first(AI::TextTransformRun::MAX_INPUT_LENGTH)
      end
    end

    def self.glossary_of(project)
      return unless project&.wiki

      page = GLOSSARY_TITLES.lazy.filter_map { project.wiki.find_page(it) }.first
      page && Assistant::Text.plain(page.text).first(GLOSSARY_LIMIT).presence
    end

    def initialize(run, project: nil)
      @run = run
      @project = project
    end

    def call
      return if @run.terminal? || @run.cancel_requested

      @run.start!
      @run.append_event("status", "status" => "running")
      buffer = +""
      reply = llm.chat(messages: [{ role: "system", content: @run.system_prompt }, { role: "user", content: @run.input }],
                       temperature: 0.2, max_tokens: 4000) do |kind, delta|
        next unless kind == :content

        buffer << delta
        flush(buffer) if buffer.length >= FLUSH_CHARS
        raise Cancelled if @run.reload.cancel_requested
      end
      flush(buffer)
      @run.append_event("completed", "text" => reply.content.to_s)
      @run.finish!("succeeded")
    rescue Cancelled
      @run.append_event("status", "status" => "cancelled")
      @run.finish!("cancelled")
    rescue Assistant::Llm::Error => e
      Rails.logger.error("[assistant] writing #{@run.id}: #{e.message}")
      message = I18n.t("assistant.writing.errors.unavailable")
      @run.append_event("error", "message" => message)
      @run.finish!("failed", error_message: message)
    end

    class Cancelled < StandardError; end

    private

    def flush(buffer)
      return if buffer.empty?

      @run.append_event("text_delta", "text" => buffer.dup)
      buffer.clear
    end

    def llm = @llm ||= Assistant::Llm.new(purpose: "writing", user: @run.user, project: @project)
  end
end
