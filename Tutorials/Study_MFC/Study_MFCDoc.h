
// Study_MFCDoc.h : interface of the CStudy_MFCDoc class
//


#pragma once

#include "FontSettings.h"


class CStudy_MFCDoc : public CDocument
{
protected: // create from serialization only
	CStudy_MFCDoc();
	DECLARE_DYNCREATE(CStudy_MFCDoc)

// Attributes
public:

// Operations
public:

// Overrides
public:
	virtual BOOL OnNewDocument();
	virtual void Serialize(CArchive& ar);
#ifdef SHARED_HANDLERS
	virtual void InitializeSearchContent();
	virtual void OnDrawThumbnail(CDC& dc, LPRECT lprcBounds);
#endif // SHARED_HANDLERS

// Implementation
public:
	virtual ~CStudy_MFCDoc();
	//virtual void DeleteContents();
	virtual void OnCloseDocument();
#ifdef _DEBUG
	virtual void AssertValid() const;
	virtual void Dump(CDumpContext& dc) const;
#endif

protected:

// Generated message map functions
protected:
	DECLARE_MESSAGE_MAP()

	afx_msg void OnSettings();
	afx_msg void OnRegTest();

private:
	void RunAugmentationTest();
	//void SwitchShaderPasses(bool enable);

public:
	FontData			m_fontData;
	Glyph3::Scene*		pScene;
	Glyph3::Actor*		pActor;
	Glyph3::RenderEffectDX11* pDiscretePathEffect;
	Glyph3::RenderEffectDX11* pFullConnectedDiscretePathEffect;
	Glyph3::RenderEffectDX11* pEuclideanPathEffect;
	Glyph3::RenderEffectDX11* pMagnifyPathEffect;
	Glyph3::RenderEffectDX11* pFinalEffect;
	Glyph3::RenderEffectDX11* pTestAugmentationEffect;

	CString				m_testImageFolder;

#ifdef SHARED_HANDLERS
	// Helper function that sets search content for a Search Handler
	void SetSearchContent(const CString& value);
#endif // SHARED_HANDLERS
};
