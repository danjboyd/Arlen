#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const vm = require("node:vm");

const VOID_TAGS = new Set(["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]);

function normalizeAttrName(name) {
  return String(name || "").trim().toLowerCase();
}

function escapeText(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function escapeAttribute(value) {
  return escapeText(value).replace(/"/g, "&quot;");
}

function isIdentifierChar(character) {
  return /[A-Za-z0-9_-]/.test(character || "");
}

function unquote(value) {
  const text = String(value || "").trim();
  if ((text.startsWith("\"") && text.endsWith("\"")) || (text.startsWith("'") && text.endsWith("'"))) {
    return text
      .slice(1, -1)
      .replace(/\\\\/g, "\\")
      .replace(/\\"/g, "\"")
      .replace(/\\'/g, "'");
  }
  return text.replace(/\\\\/g, "\\");
}

function splitOutside(value, separatorMatcher) {
  const source = String(value || "");
  const parts = [];
  let buffer = "";
  let bracketDepth = 0;
  let quote = "";
  for (let index = 0; index < source.length; index += 1) {
    const character = source[index];
    if (quote) {
      buffer += character;
      if (character === quote && source[index - 1] !== "\\") {
        quote = "";
      }
      continue;
    }
    if (character === "'" || character === "\"") {
      quote = character;
      buffer += character;
      continue;
    }
    if (character === "[") {
      bracketDepth += 1;
      buffer += character;
      continue;
    }
    if (character === "]") {
      bracketDepth -= 1;
      if (bracketDepth < 0) {
        throw new Error("invalid selector");
      }
      buffer += character;
      continue;
    }
    if (bracketDepth === 0 && separatorMatcher(character, source, index)) {
      if (buffer.trim()) {
        parts.push(buffer.trim());
      }
      buffer = "";
      continue;
    }
    buffer += character;
  }
  if (quote || bracketDepth !== 0) {
    throw new Error("invalid selector");
  }
  if (buffer.trim()) {
    parts.push(buffer.trim());
  }
  return parts;
}

function splitSelectorList(selector) {
  return splitOutside(selector, function (character) {
    return character === ",";
  });
}

function splitSelectorParts(selector) {
  return splitOutside(String(selector || "").replace(/\s*>\s*/g, " "), function (character) {
    return /\s/.test(character);
  });
}

function findClosingBracket(source, startIndex) {
  let quote = "";
  for (let index = startIndex + 1; index < source.length; index += 1) {
    const character = source[index];
    if (quote) {
      if (character === quote && source[index - 1] !== "\\") {
        quote = "";
      }
      continue;
    }
    if (character === "'" || character === "\"") {
      quote = character;
      continue;
    }
    if (character === "]") {
      return index;
    }
  }
  return -1;
}

function parseAttributeSelector(content) {
  const text = String(content || "").trim();
  if (!text) {
    throw new Error("invalid selector");
  }
  const separator = splitOutside(text, function (character) {
    return character === "=";
  });
  if (separator.length === 1) {
    return {
      name: normalizeAttrName(separator[0]),
      value: null,
    };
  }
  return {
    name: normalizeAttrName(separator[0]),
    value: unquote(separator.slice(1).join("=")),
  };
}

function parseSimpleSelector(part) {
  const source = String(part || "").trim();
  if (!source) {
    throw new Error("invalid selector");
  }

  let index = 0;
  let tagName = "";
  if (source[index] === "*") {
    tagName = "*";
    index += 1;
  } else if (/[A-Za-z]/.test(source[index])) {
    const start = index;
    while (index < source.length && isIdentifierChar(source[index])) {
      index += 1;
    }
    tagName = source.slice(start, index).toUpperCase();
  }

  const descriptor = {
    tagName: tagName,
    id: "",
    classes: [],
    attributes: [],
  };

  while (index < source.length) {
    const character = source[index];
    if (character === "#") {
      index += 1;
      const start = index;
      while (index < source.length && isIdentifierChar(source[index])) {
        index += 1;
      }
      if (index === start) {
        throw new Error("invalid selector");
      }
      descriptor.id = source.slice(start, index);
      continue;
    }
    if (character === ".") {
      index += 1;
      const start = index;
      while (index < source.length && isIdentifierChar(source[index])) {
        index += 1;
      }
      if (index === start) {
        throw new Error("invalid selector");
      }
      descriptor.classes.push(source.slice(start, index));
      continue;
    }
    if (character === "[") {
      const endIndex = findClosingBracket(source, index);
      if (endIndex < 0) {
        throw new Error("invalid selector");
      }
      descriptor.attributes.push(parseAttributeSelector(source.slice(index + 1, endIndex)));
      index = endIndex + 1;
      continue;
    }
    throw new Error("invalid selector");
  }

  return descriptor;
}

function matchesSimpleSelector(element, descriptor) {
  if (!element || element.nodeType !== 1) {
    return false;
  }
  if (descriptor.tagName && descriptor.tagName !== "*" && element.tagName !== descriptor.tagName) {
    return false;
  }
  if (descriptor.id && element.id !== descriptor.id) {
    return false;
  }
  if (descriptor.classes.length > 0) {
    const classNames = String(element.getAttribute("class") || "")
      .split(/\s+/)
      .filter(Boolean);
    for (const className of descriptor.classes) {
      if (!classNames.includes(className)) {
        return false;
      }
    }
  }
  for (const attribute of descriptor.attributes) {
    const actual = element.getAttribute(attribute.name);
    if (attribute.value == null) {
      if (actual == null) {
        return false;
      }
    } else if (String(actual || "") !== attribute.value) {
      return false;
    }
  }
  return true;
}

function matchesSelector(element, selector) {
  const selectors = splitSelectorList(selector);
  return selectors.some(function (entry) {
    const parts = splitSelectorParts(entry).map(parseSimpleSelector);
    let current = element;
    if (!matchesSimpleSelector(current, parts[parts.length - 1])) {
      return false;
    }
    for (let index = parts.length - 2; index >= 0; index -= 1) {
      current = current ? current.parentNode : null;
      while (current && !(current.nodeType === 1 && matchesSimpleSelector(current, parts[index]))) {
        current = current.parentNode;
      }
      if (!current || current.nodeType !== 1) {
        return false;
      }
    }
    return true;
  });
}

function collectDescendantElements(root) {
  const results = [];
  const stack = [];
  if (root && Array.isArray(root.childNodes)) {
    for (let index = root.childNodes.length - 1; index >= 0; index -= 1) {
      stack.push(root.childNodes[index]);
    }
  }
  while (stack.length > 0) {
    const node = stack.pop();
    if (!node) {
      continue;
    }
    if (node.nodeType === 1) {
      results.push(node);
    }
    if (Array.isArray(node.childNodes)) {
      for (let index = node.childNodes.length - 1; index >= 0; index -= 1) {
        stack.push(node.childNodes[index]);
      }
    }
  }
  return results;
}

function querySelectorAllWithin(root, selector, includeSelf) {
  const results = [];
  if (includeSelf && root && root.nodeType === 1 && matchesSelector(root, selector)) {
    results.push(root);
  }
  for (const element of collectDescendantElements(root)) {
    if (matchesSelector(element, selector)) {
      results.push(element);
    }
  }
  return results;
}

function findWhitespaceIndex(source) {
  for (let index = 0; index < source.length; index += 1) {
    if (/\s/.test(source[index])) {
      return index;
    }
  }
  return -1;
}

function parseAttributes(source) {
  const attributes = [];
  const expression = /([^\s=/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g;
  let match = null;
  while ((match = expression.exec(source))) {
    attributes.push({
      name: normalizeAttrName(match[1]),
      value: match[2] != null ? match[2] : match[3] != null ? match[3] : match[4] != null ? match[4] : "",
    });
  }
  return attributes;
}

class SimpleEventTarget {
  constructor(log) {
    this._listeners = new Map();
    this._log = log;
  }

  addEventListener(type, listener, options) {
    if (typeof listener !== "function") {
      return;
    }
    const key = String(type || "");
    if (!this._listeners.has(key)) {
      this._listeners.set(key, []);
    }
    this._listeners.get(key).push({
      listener: listener,
      once: !!(options && options.once),
    });
  }

  removeEventListener(type, listener) {
    const key = String(type || "");
    const existing = this._listeners.get(key) || [];
    this._listeners.set(
      key,
      existing.filter(function (entry) {
        return entry.listener !== listener;
      })
    );
  }

  dispatchEvent(event) {
    if (!event || !event.type) {
      return true;
    }
    if (!event.target) {
      event.target = this;
    }
    event.currentTarget = this;
    const listeners = (this._listeners.get(String(event.type)) || []).slice();
    for (const entry of listeners) {
      entry.listener.call(this, event);
      if (entry.once) {
        this.removeEventListener(event.type, entry.listener);
      }
    }
    if (this._log && event.__record !== false && (event instanceof CustomEvent || String(event.type).startsWith("arlen:"))) {
      this._log.events.push({
        name: String(event.type),
        detail: serializeValue(event.detail),
        target: targetSummary(this),
      });
    }
    return !event.defaultPrevented;
  }
}

class SimpleEvent {
  constructor(type, options) {
    const settings = options || {};
    this.type = String(type || "");
    this.bubbles = !!settings.bubbles;
    this.cancelable = !!settings.cancelable;
    this.defaultPrevented = false;
    this.target = null;
    this.currentTarget = null;
    this.__record = settings.record !== false;
  }

  preventDefault() {
    if (this.cancelable) {
      this.defaultPrevented = true;
    }
  }
}

class CustomEvent extends SimpleEvent {
  constructor(type, options) {
    super(type, options);
    this.detail = options && options.detail != null ? options.detail : {};
  }
}

class ProgressEvent extends SimpleEvent {
  constructor(type, options) {
    super(type, options);
    const settings = options || {};
    this.loaded = Number(settings.loaded || 0);
    this.total = Number(settings.total || 0);
    this.lengthComputable = !!settings.lengthComputable;
  }
}

class NodeBase extends SimpleEventTarget {
  constructor(nodeType, document, log) {
    super(log);
    this.nodeType = nodeType;
    this.ownerDocument = document || null;
    this.parentNode = null;
    this.childNodes = [];
  }

  _setOwnerDocument(document) {
    this.ownerDocument = document || null;
    for (const child of this.childNodes) {
      if (child && typeof child._setOwnerDocument === "function") {
        child._setOwnerDocument(document);
      }
    }
  }

  appendChild(node) {
    return this.insertBefore(node, null);
  }

  insertBefore(node, referenceNode) {
    if (!node) {
      return null;
    }
    if (node.parentNode && typeof node.parentNode.removeChild === "function") {
      node.parentNode.removeChild(node);
    }
    node.parentNode = this;
    if (typeof node._setOwnerDocument === "function") {
      node._setOwnerDocument(this.ownerDocument);
    }
    const referenceIndex = referenceNode ? this.childNodes.indexOf(referenceNode) : -1;
    if (referenceIndex >= 0) {
      this.childNodes.splice(referenceIndex, 0, node);
    } else {
      this.childNodes.push(node);
    }
    return node;
  }

  removeChild(node) {
    const index = this.childNodes.indexOf(node);
    if (index >= 0) {
      this.childNodes.splice(index, 1);
      node.parentNode = null;
    }
    return node;
  }

  get firstChild() {
    return this.childNodes.length > 0 ? this.childNodes[0] : null;
  }

  get children() {
    return this.childNodes.filter(function (node) {
      return node && node.nodeType === 1;
    });
  }

  get textContent() {
    return this.childNodes
      .map(function (node) {
        return node ? node.textContent : "";
      })
      .join("");
  }

  set textContent(value) {
    this.childNodes = [];
    const text = String(value == null ? "" : value);
    if (text.length > 0) {
      this.appendChild(new TextNode(text, this.ownerDocument, this._log));
    }
  }

  _replaceChildWithFragment(child, html) {
    const index = this.childNodes.indexOf(child);
    if (index < 0) {
      return;
    }
    const nodes = parseHTMLFragment(html, this.ownerDocument, this._log);
    child.parentNode = null;
    this.childNodes.splice(index, 1);
    let offset = index;
    for (const node of nodes) {
      node.parentNode = this;
      if (typeof node._setOwnerDocument === "function") {
        node._setOwnerDocument(this.ownerDocument);
      }
      this.childNodes.splice(offset, 0, node);
      offset += 1;
    }
  }
}

class TextNode extends NodeBase {
  constructor(text, document, log) {
    super(3, document, log);
    this.data = String(text || "");
  }

  get textContent() {
    return this.data;
  }

  set textContent(value) {
    this.data = String(value == null ? "" : value);
  }

  get outerHTML() {
    return escapeText(this.data);
  }
}

class ElementNode extends NodeBase {
  constructor(tagName, document, log) {
    super(1, document, log);
    this.tagName = String(tagName || "div").toUpperCase();
    this._attributes = new Map();
  }

  getAttribute(name) {
    const key = normalizeAttrName(name);
    return this._attributes.has(key) ? this._attributes.get(key) : null;
  }

  setAttribute(name, value) {
    this._attributes.set(normalizeAttrName(name), value == null ? "" : String(value));
  }

  removeAttribute(name) {
    this._attributes.delete(normalizeAttrName(name));
  }

  hasAttribute(name) {
    return this._attributes.has(normalizeAttrName(name));
  }

  get id() {
    return this.getAttribute("id") || "";
  }

  set id(value) {
    if (value == null || value === "") {
      this.removeAttribute("id");
    } else {
      this.setAttribute("id", value);
    }
  }

  get name() {
    return this.getAttribute("name") || "";
  }

  get value() {
    return this.getAttribute("value") || "";
  }

  set value(value) {
    this.setAttribute("value", value == null ? "" : value);
  }

  get max() {
    return this.getAttribute("max") || "";
  }

  set max(value) {
    this.setAttribute("max", value == null ? "" : value);
  }

  get type() {
    return this.getAttribute("type") || "";
  }

  get action() {
    return this.getAttribute("action") || "";
  }

  get href() {
    return this.getAttribute("href") || "";
  }

  get method() {
    return this.getAttribute("method") || "";
  }

  get target() {
    return this.getAttribute("target") || "";
  }

  get hidden() {
    return this.hasAttribute("hidden");
  }

  set hidden(value) {
    if (value) {
      this.setAttribute("hidden", "");
    } else {
      this.removeAttribute("hidden");
    }
  }

  get disabled() {
    return this.hasAttribute("disabled");
  }

  set disabled(value) {
    if (value) {
      this.setAttribute("disabled", "");
    } else {
      this.removeAttribute("disabled");
    }
  }

  get innerHTML() {
    return this.childNodes.map(serializeNode).join("");
  }

  set innerHTML(value) {
    this.childNodes = [];
    for (const node of parseHTMLFragment(String(value || ""), this.ownerDocument, this._log)) {
      this.appendChild(node);
    }
  }

  get outerHTML() {
    return serializeNode(this);
  }

  set outerHTML(value) {
    if (this.parentNode && typeof this.parentNode._replaceChildWithFragment === "function") {
      this.parentNode._replaceChildWithFragment(this, String(value || ""));
    }
  }

  querySelectorAll(selector) {
    return querySelectorAllWithin(this, selector, false);
  }

  querySelector(selector) {
    const results = this.querySelectorAll(selector);
    return results.length > 0 ? results[0] : null;
  }

  closest(selector) {
    let current = this;
    while (current && current.nodeType === 1) {
      if (matchesSelector(current, selector)) {
        return current;
      }
      current = current.parentNode && current.parentNode.nodeType === 1 ? current.parentNode : null;
    }
    return null;
  }

  insertAdjacentHTML(position, html) {
    const nodes = parseHTMLFragment(String(html || ""), this.ownerDocument, this._log);
    const normalizedPosition = String(position || "").toLowerCase();
    if (normalizedPosition === "afterbegin") {
      let reference = this.firstChild;
      for (const node of nodes) {
        this.insertBefore(node, reference);
      }
      return;
    }
    if (normalizedPosition === "beforeend") {
      for (const node of nodes) {
        this.appendChild(node);
      }
      return;
    }
    if (normalizedPosition === "beforebegin" && this.parentNode && typeof this.parentNode.insertBefore === "function") {
      for (const node of nodes) {
        this.parentNode.insertBefore(node, this);
      }
      return;
    }
    if (normalizedPosition === "afterend" && this.parentNode && typeof this.parentNode.insertBefore === "function") {
      const siblings = this.parentNode.childNodes;
      const index = siblings.indexOf(this);
      const reference = index >= 0 && index + 1 < siblings.length ? siblings[index + 1] : null;
      for (const node of nodes) {
        this.parentNode.insertBefore(node, reference);
      }
    }
  }

  remove() {
    if (this.parentNode && typeof this.parentNode.removeChild === "function") {
      this.parentNode.removeChild(this);
    }
  }
}

class DocumentNode extends SimpleEventTarget {
  constructor(log) {
    super(log);
    this.nodeType = 9;
    this.ownerDocument = this;
    this.readyState = "loading";
    this.body = new ElementNode("body", this, log);
    this.body.parentNode = this;
    this.documentElement = this.body;
  }

  createElement(tagName) {
    return new ElementNode(tagName, this, this._log);
  }

  createTextNode(text) {
    return new TextNode(text, this, this._log);
  }

  contains(node) {
    let current = node;
    while (current) {
      if (current === this || current === this.body) {
        return true;
      }
      current = current.parentNode;
    }
    return false;
  }

  querySelectorAll(selector) {
    const results = [];
    if (matchesSelector(this.body, selector)) {
      results.push(this.body);
    }
    return results.concat(querySelectorAllWithin(this.body, selector, false));
  }

  querySelector(selector) {
    const matches = this.querySelectorAll(selector);
    return matches.length > 0 ? matches[0] : null;
  }
}

function parseHTMLFragment(html, document, log) {
  const root = {
    childNodes: [],
    ownerDocument: document,
    appendChild(node) {
      this.childNodes.push(node);
      node.parentNode = this;
      if (typeof node._setOwnerDocument === "function") {
        node._setOwnerDocument(document);
      }
    },
  };
  const tokens = String(html || "").match(/<!--[\s\S]*?-->|<\/?[^>]+>|[^<]+/g) || [];
  const stack = [root];
  for (const token of tokens) {
    if (!token) {
      continue;
    }
    if (token.startsWith("<!--")) {
      continue;
    }
    if (token.startsWith("</")) {
      const closingName = token.slice(2, -1).trim().toLowerCase();
      for (let index = stack.length - 1; index > 0; index -= 1) {
        const node = stack[index];
        if (node.nodeType === 1 && node.tagName.toLowerCase() === closingName) {
          stack.length = index;
          break;
        }
      }
      continue;
    }
    if (token.startsWith("<")) {
      const selfClosing = token.endsWith("/>");
      const content = token.slice(1, token.length - (selfClosing ? 2 : 1)).trim();
      if (!content) {
        continue;
      }
      const whitespaceIndex = findWhitespaceIndex(content);
      const tagName = (whitespaceIndex >= 0 ? content.slice(0, whitespaceIndex) : content).trim();
      const attributeSource = whitespaceIndex >= 0 ? content.slice(whitespaceIndex + 1) : "";
      const element = new ElementNode(tagName, document, log);
      for (const attribute of parseAttributes(attributeSource)) {
        element.setAttribute(attribute.name, attribute.value);
      }
      stack[stack.length - 1].appendChild(element);
      if (!selfClosing && !VOID_TAGS.has(tagName.toLowerCase())) {
        stack.push(element);
      }
      continue;
    }
    stack[stack.length - 1].appendChild(new TextNode(token, document, log));
  }
  for (const node of root.childNodes) {
    node.parentNode = null;
  }
  return root.childNodes;
}

function serializeNode(node) {
  if (!node) {
    return "";
  }
  if (node.nodeType === 3) {
    return escapeText(node.data);
  }
  if (node.nodeType !== 1) {
    return "";
  }
  const tagName = node.tagName.toLowerCase();
  let attributes = "";
  for (const [name, value] of node._attributes.entries()) {
    if ((name === "hidden" || name === "disabled") && value === "") {
      attributes += " " + name;
    } else {
      attributes += " " + name + "=\"" + escapeAttribute(value) + "\"";
    }
  }
  if (VOID_TAGS.has(tagName)) {
    return "<" + tagName + attributes + ">";
  }
  return "<" + tagName + attributes + ">" + node.childNodes.map(serializeNode).join("") + "</" + tagName + ">";
}

function snapshotElement(element) {
  if (!element || element.nodeType !== 1) {
    return null;
  }
  const attributes = {};
  for (const [name, value] of element._attributes.entries()) {
    attributes[name] = value;
  }
  return {
    tagName: element.tagName,
    outerHTML: element.outerHTML,
    innerHTML: element.innerHTML,
    textContent: element.textContent,
    attributes: attributes,
    hidden: element.hidden,
    disabled: element.disabled,
    value: element.value,
    childElementCount: element.children.length,
  };
}

function serializeValue(value) {
  if (value == null) {
    return null;
  }
  if (value instanceof ElementNode) {
    return snapshotElement(value);
  }
  if (value instanceof TextNode) {
    return value.data;
  }
  if (Array.isArray(value)) {
    return value.map(serializeValue);
  }
  if (value instanceof Map) {
    const output = {};
    for (const [key, entry] of value.entries()) {
      output[key] = serializeValue(entry);
    }
    return output;
  }
  if (value instanceof Set) {
    return Array.from(value).map(serializeValue);
  }
  if (value instanceof URL) {
    return value.toString();
  }
  if (typeof value === "object") {
    const output = {};
    for (const key of Object.keys(value)) {
      output[key] = serializeValue(value[key]);
    }
    return output;
  }
  return value;
}

function targetSummary(target) {
  if (!target) {
    return "";
  }
  if (target.nodeType === 9) {
    return "document";
  }
  if (target.nodeType === 1) {
    if (target.id) {
      return "#" + target.id;
    }
    if (target.hasAttribute("data-arlen-live-key")) {
      return "[data-arlen-live-key=\"" + target.getAttribute("data-arlen-live-key") + "\"]";
    }
    return target.tagName.toLowerCase();
  }
  return String(target);
}

function stringifyLogValue(value) {
  if (value instanceof Error) {
    return value.stack || value.message || String(value);
  }
  if (typeof value === "string") {
    return value;
  }
  try {
    return JSON.stringify(serializeValue(value));
  } catch (error) {
    return String(value);
  }
}

class FormDataShim {
  constructor(form) {
    this._entries = [];
    if (form && typeof form.querySelectorAll === "function") {
      const controls = form.querySelectorAll("input, textarea, select");
      for (const control of controls) {
        if (!control || control.disabled) {
          continue;
        }
        const name = control.name;
        if (!name) {
          continue;
        }
        this.append(name, control.value || "");
      }
    }
  }

  append(name, value) {
    this._entries.push([String(name || ""), value == null ? "" : String(value)]);
  }

  has(name) {
    const key = String(name || "");
    return this._entries.some(function (entry) {
      return entry[0] === key;
    });
  }

  forEach(callback, thisArg) {
    for (const entry of this._entries) {
      callback.call(thisArg, entry[1], entry[0], this);
    }
  }

  [Symbol.iterator]() {
    return this._entries[Symbol.iterator]();
  }
}

class TimerManager {
  constructor() {
    this._now = 0;
    this._nextId = 1;
    this._timers = new Map();
  }

  setTimeout(callback, delay) {
    const id = this._nextId++;
    this._timers.set(id, {
      id: id,
      callback: callback,
      time: this._now + Math.max(0, Number(delay || 0)),
      interval: 0,
    });
    return id;
  }

  setInterval(callback, delay) {
    const id = this._nextId++;
    const interval = Math.max(1, Number(delay || 0));
    this._timers.set(id, {
      id: id,
      callback: callback,
      time: this._now + interval,
      interval: interval,
    });
    return id;
  }

  clearTimer(id) {
    this._timers.delete(id);
  }

  count() {
    return this._timers.size;
  }

  now() {
    return this._now;
  }

  _nextTimer() {
    const entries = Array.from(this._timers.values()).sort(function (left, right) {
      if (left.time !== right.time) {
        return left.time - right.time;
      }
      return left.id - right.id;
    });
    return entries.length > 0 ? entries[0] : null;
  }

  _runTimer(timer) {
    if (!timer || !this._timers.has(timer.id)) {
      return;
    }
    if (timer.interval > 0) {
      timer.time = this._now + timer.interval;
      this._timers.set(timer.id, timer);
      timer.callback();
      return;
    }
    this._timers.delete(timer.id);
    timer.callback();
  }

  advance(milliseconds) {
    const target = this._now + Math.max(0, Number(milliseconds || 0));
    while (true) {
      const timer = this._nextTimer();
      if (!timer || timer.time > target) {
        break;
      }
      this._now = timer.time;
      this._runTimer(timer);
    }
    this._now = target;
  }

  runAll(limit) {
    const maxIterations = Math.max(1, Number(limit || 100));
    let iterations = 0;
    while (this._timers.size > 0 && iterations < maxIterations) {
      const timer = this._nextTimer();
      if (!timer) {
        break;
      }
      this._now = timer.time;
      this._runTimer(timer);
      iterations += 1;
    }
  }
}

class FakeWebSocket extends SimpleEventTarget {
  constructor(url, log, registry) {
    super(log);
    this.url = String(url || "");
    this.readyState = FakeWebSocket.CONNECTING;
    this.sent = [];
    this.index = registry.length;
    registry.push(this);
  }

  send(payload) {
    this.sent.push(payload);
  }

  close(code, reason) {
    this._emitClose(code || 1000, reason || "");
  }

  _emitOpen() {
    this.readyState = FakeWebSocket.OPEN;
    this.dispatchEvent(new SimpleEvent("open", { record: false }));
  }

  _emitMessage(data) {
    const event = new SimpleEvent("message", { record: false });
    event.data = data;
    this.dispatchEvent(event);
  }

  _emitError() {
    this.dispatchEvent(new SimpleEvent("error", { record: false }));
  }

  _emitClose(code, reason) {
    this.readyState = FakeWebSocket.CLOSED;
    const event = new SimpleEvent("close", { record: false });
    event.code = Number(code || 1000);
    event.reason = String(reason || "");
    this.dispatchEvent(event);
  }
}

FakeWebSocket.CONNECTING = 0;
FakeWebSocket.OPEN = 1;
FakeWebSocket.CLOSING = 2;
FakeWebSocket.CLOSED = 3;

async function flushMicrotasks() {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
}

function createHarness(scenario) {
  const log = {
    events: [],
    warnings: [],
    errors: [],
    infos: [],
    requests: [],
    locations: {
      assign: [],
      replace: [],
    },
  };
  const timerManager = new TimerManager();
  const webSockets = [];
  const observers = [];
  const pending = new Map();
  const responseQueue = Array.isArray(scenario.responses) ? scenario.responses.slice() : [];

  const document = new DocumentNode(log);
  document.readyState = String(scenario.readyState || "loading");
  document.body.innerHTML = String(scenario.html || "");

  const location = {
    href: String(scenario.baseURL || "http://example.test/"),
    assign(url) {
      const value = String(url || "");
      log.locations.assign.push(value);
      this.href = value;
    },
    replace(url) {
      const value = String(url || "");
      log.locations.replace.push(value);
      this.href = value;
    },
  };

  function normalizeWebSocketURL(rawURL) {
    if (!rawURL) {
      return "";
    }
    const resolved = new URL(String(rawURL), location.href);
    if (resolved.protocol === "http:") {
      resolved.protocol = "ws:";
    } else if (resolved.protocol === "https:") {
      resolved.protocol = "wss:";
    }
    return resolved.toString();
  }

  function normalizeHeaders(headers) {
    const output = {};
    if (!headers) {
      return output;
    }
    if (typeof headers.forEach === "function" && !Array.isArray(headers)) {
      headers.forEach(function (value, key) {
        output[String(key)] = String(value);
      });
      return output;
    }
    for (const key of Object.keys(headers)) {
      output[String(key)] = String(headers[key]);
    }
    return output;
  }

  function headerReader(headers) {
    const normalized = {};
    for (const key of Object.keys(headers || {})) {
      normalized[normalizeAttrName(key)] = String(headers[key]);
    }
    return {
      get(name) {
        return normalized[normalizeAttrName(name)] || "";
      },
    };
  }

  function serializeRequestBody(body) {
    if (body instanceof FormDataShim) {
      return {
        kind: "form-data",
        entries: Array.from(body).map(function (entry) {
          return {
            name: entry[0],
            value: entry[1],
          };
        }),
      };
    }
    if (body == null) {
      return null;
    }
    if (typeof body === "string") {
      return body;
    }
    if (body instanceof URLSearchParams) {
      return body.toString();
    }
    return serializeValue(body);
  }

  function normalizeUploadProgress(entries, delayMilliseconds) {
    const progressEntries = Array.isArray(entries) ? entries : [];
    if (progressEntries.length === 0) {
      return [];
    }
    return progressEntries.map(function (entry, index) {
      if (Array.isArray(entry)) {
        return {
          loaded: Number(entry[0] || 0),
          total: Number(entry[1] || 0),
          delayMs: Math.round((Math.max(1, Number(delayMilliseconds || 0)) * (index + 1)) / progressEntries.length),
        };
      }
      return {
        loaded: Number(entry.loaded || 0),
        total: Number(entry.total || 0),
        delayMs: Number(entry.delayMs != null ? entry.delayMs : entry.delay_ms != null ? entry.delay_ms : Math.round((Math.max(1, Number(delayMilliseconds || 0)) * (index + 1)) / progressEntries.length)),
      };
    });
  }

  function dequeueResponse(expectedTransport, fallbackURL) {
    if (responseQueue.length === 0) {
      throw new Error("no queued response for " + expectedTransport);
    }
    const entry = responseQueue.shift() || {};
    if (entry.transport && String(entry.transport) !== expectedTransport) {
      throw new Error("expected " + expectedTransport + " response but found " + entry.transport);
    }
    return {
      status: Number(entry.status != null ? entry.status : 200),
      headers: normalizeHeaders(entry.headers || {}),
      body: typeof entry.body === "string" ? entry.body : "",
      url: String(entry.url || fallbackURL || location.href),
      redirected: !!entry.redirected,
      delayMs: Math.max(0, Number(entry.delayMs != null ? entry.delayMs : entry.delay_ms != null ? entry.delay_ms : 0)),
      uploadProgress: normalizeUploadProgress(entry.uploadProgress || entry.upload_progress, entry.delayMs || entry.delay_ms || 0),
    };
  }

  function delayedValue(delayMilliseconds, producer) {
    return new Promise(function (resolve, reject) {
      const finish = function () {
        try {
          resolve(producer());
        } catch (error) {
          reject(error);
        }
      };
      if (delayMilliseconds > 0) {
        timerManager.setTimeout(finish, delayMilliseconds);
      } else {
        finish();
      }
    });
  }

  const fakeConsole = {
    log() {
      log.infos.push(Array.from(arguments).map(stringifyLogValue).join(" "));
    },
    warn() {
      log.warnings.push(Array.from(arguments).map(stringifyLogValue).join(" "));
    },
    error() {
      log.errors.push(Array.from(arguments).map(stringifyLogValue).join(" "));
    },
  };

  const window = new SimpleEventTarget(log);
  window.document = document;
  window.location = location;
  window.console = fakeConsole;
  window.setTimeout = timerManager.setTimeout.bind(timerManager);
  window.clearTimeout = timerManager.clearTimer.bind(timerManager);
  window.setInterval = timerManager.setInterval.bind(timerManager);
  window.clearInterval = timerManager.clearTimer.bind(timerManager);
  window.Promise = Promise;
  window.URL = URL;
  window.URLSearchParams = URLSearchParams;
  window.FormData = FormDataShim;
  window.CustomEvent = CustomEvent;
  window.WebSocket = function (url) {
    return new FakeWebSocket(url, log, webSockets);
  };
  window.WebSocket.CONNECTING = FakeWebSocket.CONNECTING;
  window.WebSocket.OPEN = FakeWebSocket.OPEN;
  window.WebSocket.CLOSING = FakeWebSocket.CLOSING;
  window.WebSocket.CLOSED = FakeWebSocket.CLOSED;

  if (!scenario.disableIntersectionObserver) {
    window.IntersectionObserver = class {
      constructor(callback, options) {
        this.callback = callback;
        this.options = options || {};
        this.targets = new Set();
        observers.push(this);
      }

      observe(target) {
        this.targets.add(target);
      }

      unobserve(target) {
        this.targets.delete(target);
      }

      disconnect() {
        this.targets.clear();
      }
    };
  }

  window.fetch = function (url, options) {
    const requestHeaders = normalizeHeaders(options && options.headers);
    log.requests.push({
      transport: "fetch",
      url: String(url || ""),
      method: String((options && options.method) || "GET").toUpperCase(),
      headers: requestHeaders,
      body: serializeRequestBody(options && options.body),
    });
    const response = dequeueResponse("fetch", url);
    return delayedValue(response.delayMs, function () {
      return {
        status: response.status,
        redirected: response.redirected,
        url: response.url,
        headers: headerReader(response.headers),
        text: async function () {
          return response.body;
        },
      };
    });
  };

  class XMLHttpRequestShim extends SimpleEventTarget {
    constructor() {
      super(log);
      this.upload = new SimpleEventTarget(log);
      this._headers = {};
      this._method = "GET";
      this._url = location.href;
      this.status = 0;
      this.responseText = "";
      this.responseURL = "";
      this.withCredentials = false;
    }

    open(method, url) {
      this._method = String(method || "GET").toUpperCase();
      this._url = String(url || location.href);
    }

    setRequestHeader(name, value) {
      this._headers[String(name)] = String(value);
    }

    getResponseHeader(name) {
      return this._responseHeaders ? this._responseHeaders[normalizeAttrName(name)] || "" : "";
    }

    send(body) {
      log.requests.push({
        transport: "xhr",
        url: this._url,
        method: this._method,
        headers: normalizeHeaders(this._headers),
        body: serializeRequestBody(body),
      });
      const response = dequeueResponse("xhr", this._url);
      this._responseHeaders = {};
      for (const key of Object.keys(response.headers)) {
        this._responseHeaders[normalizeAttrName(key)] = String(response.headers[key]);
      }

      const finalize = () => {
        this.status = response.status;
        this.responseText = response.body;
        this.responseURL = response.url;
        this.dispatchEvent(new SimpleEvent("load", { record: false }));
      };

      for (const entry of response.uploadProgress) {
        const callback = () => {
          this.upload.dispatchEvent(
            new ProgressEvent("progress", {
              loaded: entry.loaded,
              total: entry.total,
              lengthComputable: entry.total > 0,
              record: false,
            })
          );
        };
        if (entry.delayMs > 0) {
          timerManager.setTimeout(callback, entry.delayMs);
        } else {
          callback();
        }
      }

      if (response.delayMs > 0) {
        timerManager.setTimeout(finalize, response.delayMs);
      } else {
        finalize();
      }
    }
  }

  window.XMLHttpRequest = XMLHttpRequestShim;

  const context = {
    window: window,
    document: document,
    console: fakeConsole,
    fetch: window.fetch,
    CustomEvent: CustomEvent,
    FormData: FormDataShim,
    XMLHttpRequest: XMLHttpRequestShim,
    WebSocket: window.WebSocket,
    URL: URL,
    URLSearchParams: URLSearchParams,
    Promise: Promise,
    setTimeout: window.setTimeout,
    clearTimeout: window.clearTimeout,
    setInterval: window.setInterval,
    clearInterval: window.clearInterval,
  };

  if (window.IntersectionObserver) {
    context.IntersectionObserver = window.IntersectionObserver;
  }

  function resolveWebSocket(action) {
    if (action && action.socketIndex != null) {
      const socket = webSockets[Number(action.socketIndex)];
      if (!socket) {
        throw new Error("websocket not found at index " + action.socketIndex);
      }
      return socket;
    }
    let rawURL = "";
    if (action && action.selector) {
      rawURL = attributeValue(requireElement(action.selector), "data-arlen-live-stream");
    } else {
      rawURL = String((action && action.url) || "");
    }
    if (!rawURL) {
      throw new Error("websocket action requires url, selector, or socketIndex");
    }
    const normalized = normalizeWebSocketURL(rawURL);
    for (let index = webSockets.length - 1; index >= 0; index -= 1) {
      if (webSockets[index] && webSockets[index].url === normalized) {
        return webSockets[index];
      }
    }
    throw new Error("websocket not found for " + rawURL);
  }

  function snapshotWebSocket(socket) {
    if (!socket) {
      return null;
    }
    return {
      index: socket.index,
      url: socket.url,
      readyState: socket.readyState,
      sent: serializeValue(socket.sent),
    };
  }

  function requireElement(selector) {
    const element = document.querySelector(String(selector || ""));
    if (!element) {
      throw new Error("selector did not resolve: " + selector);
    }
    return element;
  }

  function triggerIntersection(selector, isIntersecting) {
    const element = requireElement(selector);
    for (const observer of observers) {
      if (observer.targets.has(element)) {
        observer.callback(
          [
            {
              target: element,
              isIntersecting: isIntersecting !== false,
              intersectionRatio: isIntersecting === false ? 0 : 1,
            },
          ],
          observer
        );
      }
    }
  }

  async function invokeMaybeAsync(action, value) {
    if (value && typeof value.then === "function") {
      if (action.await === false) {
        const pendingKey = String(action.id || "pending");
        pending.set(pendingKey, value);
        return {
          pending: pendingKey,
        };
      }
      return serializeValue(await value);
    }
    return serializeValue(value);
  }

  async function runAction(action) {
    const type = String((action && action.type) || "");
    switch (type) {
      case "start":
        return invokeMaybeAsync(action, context.window.ArlenLive.start());
      case "apply_payload":
        return invokeMaybeAsync(action, context.window.ArlenLive.applyPayload(action.payload || {}));
      case "submit_form":
        return invokeMaybeAsync(
          action,
          context.window.ArlenLive.__testing.submitLiveForm(
            requireElement(action.selector),
            action.submitter ? requireElement(action.submitter) : null
          )
        );
      case "follow_link":
        return invokeMaybeAsync(action, context.window.ArlenLive.__testing.followLiveLink(requireElement(action.selector)));
      case "fetch_region":
        return invokeMaybeAsync(
          action,
          context.window.ArlenLive.__testing.fetchLiveRegion(requireElement(action.selector), action.reason || "manual")
        );
      case "activate_region":
        return invokeMaybeAsync(action, context.window.ArlenLive.__testing.activateRegion(requireElement(action.selector)));
      case "scan_streams":
        return invokeMaybeAsync(action, context.window.ArlenLive.__testing.scanStreams());
      case "handle_response":
        {
          const response = Object.assign({}, action.response || {});
          response.headers = headerReader(response.headers || {});
          return invokeMaybeAsync(
            action,
            context.window.ArlenLive.__testing.handleLiveTextResponse(
              response,
              action.fallbackURL || response.url || location.href,
              action.options || {}
            )
          );
        }
      case "websocket_open":
        resolveWebSocket(action)._emitOpen();
        return snapshotWebSocket(resolveWebSocket(action));
      case "websocket_message":
        resolveWebSocket(action)._emitMessage(
          typeof action.data === "string" ? action.data : JSON.stringify(action.data == null ? "" : action.data)
        );
        return snapshotWebSocket(resolveWebSocket(action));
      case "websocket_error":
        resolveWebSocket(action)._emitError();
        return snapshotWebSocket(resolveWebSocket(action));
      case "websocket_close":
        resolveWebSocket(action)._emitClose(action.code || 1000, action.reason || "");
        return snapshotWebSocket(resolveWebSocket(action));
      case "websocket_summary":
        return serializeValue(webSockets.map(snapshotWebSocket));
      case "advance_time":
        timerManager.advance(Number(action.ms || 0));
        await flushMicrotasks();
        return {
          now: timerManager.now(),
          pendingTimers: timerManager.count(),
        };
      case "run_all_timers":
        timerManager.runAll(action.limit || 50);
        await flushMicrotasks();
        return {
          now: timerManager.now(),
          pendingTimers: timerManager.count(),
        };
      case "await":
        if (!pending.has(String(action.id || "pending"))) {
          throw new Error("pending promise not found: " + String(action.id || "pending"));
        }
        {
          const key = String(action.id || "pending");
          const result = await pending.get(key);
          pending.delete(key);
          return serializeValue(result);
        }
      case "trigger_intersection":
        triggerIntersection(action.selector, action.isIntersecting !== false);
        await flushMicrotasks();
        return {
          selector: action.selector,
        };
      case "snapshot":
        return snapshotElement(requireElement(action.selector));
      case "set_ready_state":
        document.readyState = String(action.value || "loading");
        return document.readyState;
      default:
        throw new Error("unknown runtime action: " + type);
    }
  }

  async function evaluateRuntime(runtimeSource) {
    vm.runInNewContext(String(runtimeSource || ""), context, {
      filename: "arlen_live_runtime.js",
    });
    await flushMicrotasks();
  }

  async function run(runtimeSource, actions, selectorsToInspect) {
    await evaluateRuntime(runtimeSource);
    const actionResults = [];
    for (const action of Array.isArray(actions) ? actions : []) {
      actionResults.push(await runAction(action));
      await flushMicrotasks();
    }

    const elements = {};
    for (const selector of Array.isArray(selectorsToInspect) ? selectorsToInspect : []) {
      elements[selector] = snapshotElement(document.querySelector(selector));
    }

    return {
      actionResults: serializeValue(actionResults),
      documentHTML: document.body.innerHTML,
      elements: elements,
      events: serializeValue(log.events),
      warnings: log.warnings.slice(),
      errors: log.errors.slice(),
      infos: log.infos.slice(),
      requests: serializeValue(log.requests),
      webSockets: serializeValue(webSockets.map(snapshotWebSocket)),
      locations: serializeValue(log.locations),
      timers: {
        now: timerManager.now(),
        pending: timerManager.count(),
      },
    };
  }

  return {
    run: run,
  };
}

async function main() {
  const input = fs.readFileSync(0, "utf8");
  const scenario = input ? JSON.parse(input) : {};
  const harness = createHarness(scenario);
  const result = await harness.run(scenario.runtime || "", scenario.actions || [], scenario.inspect || []);
  process.stdout.write(JSON.stringify(result));
}

main().catch(function (error) {
  process.stderr.write((error && error.stack) || String(error) || "live runtime harness error");
  process.stderr.write("\n");
  process.exit(1);
});
