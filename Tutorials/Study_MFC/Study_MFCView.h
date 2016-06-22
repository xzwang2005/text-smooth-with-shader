
// Study_MFCView.h : interface of the CStudy_MFCView class
//

#pragma once
#include "colorSmoothRenderTask.h"

class CStudy_MFCView : public CView
{
protected: // create from serialization only
	CStudy_MFCView();
	DECLARE_DYNCREATE(CStudy_MFCView)

// Attributes
public:
	CStudy_MFCDoc* GetDocument() const;
	static CStudy_MFCView * GetView();

// Operations
public:

// Overrides
public:
	virtual void OnDraw(CDC* pDC);  // overridden to draw this view
	virtual BOOL PreCreateWindow(CREATESTRUCT& cs);
	virtual void OnInitialUpdate();
	virtual void OnDestroy();
	virtual void OnUpdate(CView* pSender, LPARAM lHint, CObject* pHint);
	
	afx_msg BOOL OnEraseBkgnd(CDC* pDC);
	afx_msg void OnLButtonDown(UINT nFlags, CPoint point);
	afx_msg void OnLButtonUp(UINT nFlags, CPoint point);
	afx_msg void OnMouseMove(UINT nFlags, CPoint point);
	afx_msg void OnSize(UINT nType, int cx, int cy);
	afx_msg BOOL OnMouseWheel(UINT nFlags, short zDelta, CPoint pt);
	afx_msg void OnKeyUp(UINT nChar, UINT nRepCnt, UINT nFlags);
	//afx_msg BOOL OnSetCursor(CWnd* pWnd, UINT nHitTest, UINT message);

protected:

// Implementation
public:
	virtual ~CStudy_MFCView();
#ifdef _DEBUG
	virtual void AssertValid() const;
	virtual void Dump(CDumpContext& dc) const;
#endif

private:
	bool				m_bInitialized;

// Generated message map functions
protected:
	DECLARE_MESSAGE_MAP()

public:
	Glyph3::Camera*								pCamera;
	ColorSmoothRenderTask*						m_pColorSmoothView;
	Glyph3::ViewTextOverlay*					pTextOverlayView;
	Glyph3::Timer*								m_pTimer;
	int											SwapChain;
	Glyph3::VectorParameterDX11*			m_pWindowSizeParameter;
	Glyph3::VectorParameterDX11*			m_pMagnifyParameter;
	Glyph3::ShaderResourceParameterDX11*	m_pInputParameter;
	Glyph3::VectorParameterDX11*			m_pShowOriginalParameter;
	
	Glyph3::Vector4f				WindowSize;
	Glyph3::Vector2f				MagnifyCoefficient;
	Glyph3::Vector2f				ShowOriginalImage;
	Glyph3::Vector2f				m_DesktopRes;
	int						m_Sampler;
	Glyph3::ResourcePtr		m_Texture;
	Glyph3::ResourcePtr		m_DepthTarget;
	Glyph3::ResourcePtr		m_RenderTarget;

	CPoint					m_lastMousePos;
	CPoint					m_deltaPt;
	CPoint					m_wndAnchor;		// upper-left point of the window
	bool					m_firstDown;
	D3D11_BOX				m_copyBox;
	
	CString/*std::wstring*/			m_fileName;
	CString							m_dirName;

	void GenerateText();
	void LoadTextImage();
	int GetSwapChain();
	afx_msg void OnFileOpen();
};

#ifndef _DEBUG  // debug version in Study_MFCView.cpp
inline CStudy_MFCDoc* CStudy_MFCView::GetDocument() const
   { return reinterpret_cast<CStudy_MFCDoc*>(m_pDocument); }
#endif

