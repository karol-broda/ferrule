package tree_sitter_ferrule_test

import (
	"testing"

	tree_sitter "github.com/tree-sitter/go-tree-sitter"
	tree_sitter_ferrule "github.com/karol-broda/ferrule/bindings/go"
)

func TestCanLoadGrammar(t *testing.T) {
	language := tree_sitter.NewLanguage(tree_sitter_ferrule.Language())
	if language == nil {
		t.Errorf("Error loading ferrule grammar")
	}
}
