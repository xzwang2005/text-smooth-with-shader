
// Study_MFCView.cpp : implementation of the CStudy_MFCView class
//

#include "stdafx.h"
// SHARED_HANDLERS can be defined in an ATL project implementing preview, thumbnail
// and search filter handlers and allows sharing of document code with that project.
#ifndef SHARED_HANDLERS
#include "Study_MFC.h"
#endif

#include "Study_MFCDoc.h"
#include "Study_MFCView.h"
#include "SamplerStateConfigDX11.h"
#include "Texture2dDX11.h"
#include "Texture2dConfigDX11.h"
#include "AppSettings.h"

#ifdef _DEBUG
#define new DEBUG_NEW
#undef THIS_FILE
static char THIS_FILE[] = __FILE__;
#endif


// CStudy_MFCView

IMPLEMENT_DYNCREATE(CStudy_MFCView, CView)

BEGIN_MESSAGE_MAP(CStudy_MFCView, CView)
	ON_WM_PAINT()
	ON_WM_ERASEBKGND()
	ON_WM_DESTROY()
	ON_WM_LBUTTONDOWN()
	ON_WM_LBUTTONUP()
	ON_WM_MOUSEMOVE()
	ON_WM_MOUSEWHEEL()
	ON_WM_SIZE()
	ON_WM_KEYUP()
	//ON_WM_SETCURSOR()
	ON_COMMAND(ID_FILE_OPEN, &CStudy_MFCView::OnFileOpen)
END_MESSAGE_MAP()

// CStudy_MFCView construction/destruction

CStudy_MFCView::CStudy_MFCView()
{
	// TODO: add construction code here
	m_pTimer = nullptr;
	pCamera = nullptr;
	pTextOverlayView = nullptr;
	m_pColorSmoothView = nullptr;
	m_pInputParameter = nullptr;
	SwapChain = -1;
}

CStudy_MFCView::~CStudy_MFCView()
{
}

BOOL CStudy_MFCView::PreCreateWindow(CREATESTRUCT& cs)
{
	// TODO: Modify the Window class or styles here by modifying
	//  the CREATESTRUCT cs

	return CView::PreCreateWindow(cs);
}

void CStudy_MFCView::OnInitialUpdate()
{
	m_bInitialized = false;
	CView::OnInitialUpdate();

	Glyph3::RendererDX11* pRenderer = Glyph3::RendererDX11::Get();

	m_pTimer = new Glyph3::Timer();
	m_pTimer->Update();

	m_firstDown = true;

	m_DesktopRes = pRenderer->GetDesktopResolution();

	//Glyph3::Texture2dConfigDX11 TexConfig;
	//TexConfig.SetColorBuffer(static_cast<unsigned int>(m_DesktopRes.x), static_cast<unsigned int>(m_DesktopRes.y));
	//TexConfig.SetBindFlags(D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE);
	//TexConfig.SetFormat(DXGI_FORMAT_R8G8B8A8_UNORM);
	//m_OffscreenTexture = pRenderer->CreateTexture2D(&TexConfig, 0);

	//// Next we create a depth buffer for use in the traditional rendering
	//// pipeline.
	//Glyph3::Texture2dConfigDX11 DepthConfig;
	//DepthConfig.SetDepthBuffer(static_cast<unsigned int>(m_DesktopRes.x), static_cast<unsigned int>(m_DesktopRes.y));
	//m_DepthTarget = pRenderer->CreateTexture2D(&DepthConfig, 0);

	// prepare the swap chain
	RECT client;
	this->GetClientRect(&client);

	LONG width = client.right - client.left;
	LONG height = client.bottom - client.top;

	// Create a swap chain for the window.
	Glyph3::SwapChainConfigDX11 Config;
	Config.SetWidth(width);
	Config.SetHeight(height);
	Config.SetOutputWindow(this->GetSafeHwnd());

	SwapChain = pRenderer->CreateSwapChain(&Config);

	// Acquire the swap chain's render target reference to use in the render views.

	m_RenderTarget = pRenderer->GetSwapChainResource(SwapChain);

	// create depth buffer
	Glyph3::Texture2dConfigDX11 DepthConfig;
	DepthConfig.SetDepthBuffer(width, height);
	m_DepthTarget = pRenderer->CreateTexture2D(&DepthConfig, 0);
	// Create and configure the render views for use in our camera.

	//m_pPerspectiveView = new Glyph3::ViewPerspective(*pRenderer, /*m_OffscreenTexture*/ m_RenderTarget, m_DepthTarget);
	//m_pPerspectiveView->SetBackColor(Glyph3::Vector4f(0.6f, 0.6f, 0.9f, 1.0f));

	CStudy_MFCDoc* pDoc = GetDocument();
	pDoc->SetTitle(L"Classic smoothing Test App");
	int magnifyLevel = pDoc->m_fontData.magnifyLevel;

	m_pColorSmoothView = new ColorSmoothRenderTask(*pRenderer, m_RenderTarget, magnifyLevel);

	pTextOverlayView = new Glyph3::ViewTextOverlay(*pRenderer, m_RenderTarget);

	// Create and configure the camera for this view.
	pCamera = new Glyph3::Camera();
	pCamera->Spatial().SetTranslation(Glyph3::Vector3f(0.0f, 0.0f, -1.0f));
	//pCamera->SetCameraView(m_pPerspectiveView);
	pCamera->SetCameraView(m_pColorSmoothView);
	pCamera->SetOverlayView(pTextOverlayView);
	pCamera->SetOrthographicParams(0.1f, 1000.0f, static_cast<float>(width), static_cast<float>(height));

	GetDocument()->pScene->AddCamera(pCamera);

	// get reference to shader parameters
	m_pInputParameter = pRenderer->m_pParamMgr->GetShaderResourceParameterRef(std::wstring(L"InputMap"));
	m_pWindowSizeParameter = pRenderer->m_pParamMgr->GetVectorParameterRef(std::wstring(L"WindowSize"));
	m_pMagnifyParameter = pRenderer->m_pParamMgr->GetVectorParameterRef(std::wstring(L"MagnifyLevel"));
	m_pShowOriginalParameter = pRenderer->m_pParamMgr->GetVectorParameterRef(std::wstring(L"ShowOriginal"));

	WindowSize = Glyph3::Vector4f(0.0f, 0.0f, 0.0f, 0.0f);
	m_pWindowSizeParameter->InitializeParameterData(&WindowSize);

	MagnifyCoefficient = Glyph3::Vector2f((float)magnifyLevel, (float)magnifyLevel);
	m_pMagnifyParameter->InitializeParameterData(&MagnifyCoefficient);

	ShowOriginalImage = Glyph3::Vector2f((float)DisplayMode::Value, (float)DisplayMode::Value);
	m_pShowOriginalParameter->InitializeParameterData(&ShowOriginalImage);

	//// create a sampler
	//Glyph3::SamplerStateConfigDX11 SamplerConfig;
	//SamplerConfig.Filter = D3D11_FILTER_MIN_MAG_POINT_MIP_LINEAR;

	//m_Sampler = pRenderer->CreateSamplerState(&SamplerConfig);

	//Glyph3::SamplerParameterDX11* pSamplerParameter =
	//	pRenderer->m_pParamMgr->GetSamplerStateParameterRef(std::wstring(L"LinearSampler"));
	//pSamplerParameter->InitializeParameterData(&m_Sampler);

	//WindowSize = Glyph3::Vector4f((float)width, (float)height, 0.0f, 0.0f);
	//m_pWindowSizeParameter->InitializeParameterData(&WindowSize);

	m_Texture = nullptr;
	m_fileName = L"../Data/Textures/text.png";
	m_dirName.Empty();
	//Glyph3::Texture2dDX11* pTex = pRenderer->GetTexture2DByIndex(m_Texture->m_iResource);
	//D3D11_TEXTURE2D_DESC desc = pTex->GetActualDescription();
	//ImageSize = Glyph3::Vector4f((float)desc.Width, (float)desc.Height, 0.0f, 0.0f);
	//m_pImageSizeParameter->InitializeParameterData( &ImageSize );

	//ViewingParams = Glyph3::Vector4f(0.5f, 0.5f, 1.0f, 1.0f);
	//m_pViewingParamsParameter->InitializeParameterData( &ViewingParams );

	m_bInitialized = true;
	//GenerateTextInMemory();
}

BOOL CStudy_MFCView::OnEraseBkgnd(CDC* pDC)
{
	return FALSE;
}

void CStudy_MFCView::OnKeyUp(UINT nChar, UINT nRepCnt, UINT nFlags)
{
	if (m_bInitialized)
	{
		UINT code = ::MapVirtualKey(nChar, MAPVK_VK_TO_CHAR);
		if (code == (UINT)DisplayMode::IncKey)
		{
			DisplayMode::Increment();
			ShowOriginalImage = Glyph3::Vector2f((float)DisplayMode::Value, (float)DisplayMode::Value);
			m_pShowOriginalParameter->InitializeParameterData(&ShowOriginalImage);
		}
		else if (code == (UINT)DisplayMode::DecKey)
		{
			DisplayMode::Decrement();
			ShowOriginalImage = Glyph3::Vector2f((float)DisplayMode::Value, (float)DisplayMode::Value);
			m_pShowOriginalParameter->InitializeParameterData(&ShowOriginalImage);
		}
		
	}

	CWnd::OnKeyUp(nChar, nRepCnt, nFlags);

	Invalidate();
}

void CStudy_MFCView::LoadTextImage()
{
	// resize render target and viewport
	CStudy_MFCDoc* pDoc = GetDocument();
	int magnifyLevel = pDoc->m_fontData.magnifyLevel;
	//m_Texture = Glyph3::RendererDX11::Get()->LoadTexture((LPCTSTR)m_fileName);
	m_Texture = Glyph3::RendererDX11::Get()->LoadTextureWithFullFileName((LPCTSTR)m_fileName);
	m_pInputParameter->InitializeParameterData(&m_Texture->m_iResourceSRV);

	// get texture size
	D3D11_TEXTURE2D_DESC desc = m_Texture->m_pTexture2dConfig->GetTextureDesc();
	WindowSize.z = desc.Width;
	WindowSize.w = desc.Height;
	
	m_pWindowSizeParameter->InitializeParameterData(&WindowSize);
}

// CStudy_MFCView drawing

void CStudy_MFCView::OnDraw(CDC* pDC)
{
	CStudy_MFCDoc* pDoc = GetDocument();
	ASSERT_VALID(pDoc);
	if (!pDoc)
		return;

	if (!m_Texture) {
		GenerateText();
		LoadTextImage();
	}

	m_pTimer->Update();
	RECT rc;
	GetClientRect(&rc);
	float width = rc.right - rc.left;
	float height = rc.bottom - rc.top;
	std::wstringstream out;
	//out << L"Left button to pan" << std::endl;
	//out << L"Mouse wheel to change magnify level " << std::endl;
	//out << L"Options menu to set font/text" << std::endl;
	out << L"Magnify level: " << pDoc->m_fontData.magnifyLevel << std::endl;
	out << L"Font: " << (LPCTSTR)(pDoc->m_fontData.fontName) << std::endl;
	out << DisplayMode::ToString() << std::endl;
	pTextOverlayView->WriteText(out.str(), Glyph3::Matrix4f::TranslationMatrix(width - 195.0f, 10.0f, 0.0f), Glyph3::Vector4f(0.3f, 0.1f, 0.3f, 1.0f));

	//pCamera->SetScene(pDoc->pScene);
	pCamera->RenderFrame(Glyph3::RendererDX11::Get());


	Glyph3::RendererDX11::Get()->Present(this->GetSafeHwnd(), SwapChain);
}

CStudy_MFCView* CStudy_MFCView::GetView()
{
	CFrameWnd *pFrame = (CFrameWnd *)(AfxGetApp()->m_pMainWnd);
	CView * pView = pFrame->GetActiveView();

	if (!pView) return NULL;

	// Fail if view is of wrong kind
	// (this could occur with splitter windows, or additional
	// views on a single document
	if (!pView->IsKindOf(RUNTIME_CLASS(CStudy_MFCView)))
		return NULL;

	return (CStudy_MFCView *)pView;
}

void CStudy_MFCView::OnUpdate(CView* pSender, LPARAM lHint, CObject* pHint)
{
	if (m_bInitialized) {
		GenerateText();
		LoadTextImage();
	}
	CView::OnUpdate(pSender, lHint, pHint);
}

// this method does not work
//void CStudy_MFCView::GenerateTextInMemory()
//{
//	CStudy_MFCDoc* pDoc = GetDocument();
//	ASSERT_VALID(pDoc);
//	if (!pDoc)
//		return;
//
//	using namespace Gdiplus;
//	Bitmap bitmap(static_cast<int>(m_DesktopRes.x), static_cast<int>(m_DesktopRes.y));
//	Graphics* graphics = Graphics::FromImage(&bitmap);
//	Gdiplus::Status res = graphics->SetTextRenderingHint(TextRenderingHintSingleBitPerPixelGridFit);
//
//	SolidBrush bkgBrush(Color(255, 255, 255, 255));
//	graphics->FillRectangle(&bkgBrush, 0, 0, INT(m_DesktopRes.x), INT(m_DesktopRes.y));
//
//	Gdiplus::PointF origin(0.0f, 0.0f);
//	Color textColor = Color(255, 0, 0, 0);
//	textColor.SetFromCOLORREF(pDoc->m_fontData.fontColor);
//	SolidBrush textBrush(textColor);
//
//	for (int fsize = pDoc->m_fontData.minFontSize; fsize <= pDoc->m_fontData.maxFontSize; fsize++)
//	{
//		Gdiplus::Font cfont(pDoc->m_fontData.fontName, fsize);
//		res = graphics->DrawString(
//			pDoc->m_fontData.sampleText,
//			-1,
//			&cfont,
//			origin,
//			&textBrush);
//		origin.Y += 1.6 * fsize;
//
//		Gdiplus::Font italicfont(pDoc->m_fontData.fontName, fsize, FontStyle::FontStyleItalic);
//		graphics->DrawString(
//			pDoc->m_fontData.sampleText,
//			-1,
//			&italicfont,
//			origin,
//			&textBrush);
//		origin.Y += 1.6 * fsize;
//	}
//
//	Gdiplus::BitmapData bitmapData;
//	Gdiplus::Rect rect(0, 0, bitmap.GetWidth(), bitmap.GetHeight());
//
//	//get the bitmap data
//	if (Gdiplus::Ok == bitmap.LockBits(
//		&rect,
//		Gdiplus::ImageLockModeRead,        
//		bitmap.GetPixelFormat(),
//		&bitmapData
//		))
//	{
//		//get the lenght of the bitmap data in bytes
//		int len = bitmapData.Height * std::abs(bitmapData.Stride);
//
//		m_Texture = Glyph3::RendererDX11::Get()->LoadTexture((void*)bitmapData.Scan0, len);
//		m_pInputParameter->InitializeParameterData(&m_Texture->m_iResourceSRV);
//
//		bitmap.UnlockBits(&bitmapData);
//	}
//
//	delete graphics;
//}
void CStudy_MFCView::GenerateText()
{
	CStudy_MFCDoc* pDoc = GetDocument();
	ASSERT_VALID(pDoc);
	if (!pDoc)
		return;

	using namespace Gdiplus;
	CDC* pDC = GetDC();
	CBitmap bitmap;
	bitmap.CreateCompatibleBitmap(pDC, static_cast<int>(m_DesktopRes.x), static_cast<int>(m_DesktopRes.y));
	CImage image;

	image.Attach(bitmap);
	Graphics graphics(image.GetDC());
	Gdiplus::Status res = graphics.SetTextRenderingHint(TextRenderingHintSingleBitPerPixelGridFit);

	SolidBrush bkgBrush(Color(255, 255, 255, 255));
	graphics.FillRectangle(&bkgBrush, 0, 0, INT(m_DesktopRes.x), INT(m_DesktopRes.y));

	Gdiplus::PointF origin(0.0f, 0.0f);
	Color textColor = Color(255, 0, 0, 0);
	textColor.SetFromCOLORREF(pDoc->m_fontData.fontColor);
	SolidBrush textBrush(textColor);

	for (int fsize = pDoc->m_fontData.minFontSize; fsize <= pDoc->m_fontData.maxFontSize; fsize++)
	{
		Gdiplus::Font cfont(pDoc->m_fontData.fontName, fsize);
		CString line;
		line.Format(L"%s %d -- %s", L"font size ", fsize, pDoc->m_fontData.sampleText);
		res = graphics.DrawString(
			line,
			-1,
			&cfont,
			origin,
			&textBrush);
		origin.Y += 1.6 * fsize;

		Gdiplus::Font italicfont(pDoc->m_fontData.fontName, fsize, FontStyle::FontStyleItalic);
		graphics.DrawString(
			line,
			-1,
			&italicfont,
			origin,
			&textBrush);
		origin.Y += 1.6 * fsize;
	}
	image.ReleaseDC();

	HRESULT hr = image.Save(_T("../Data/Textures/text.png"), ImageFormatPNG);

	//BITMAP bmi;
	//if (bitmap.GetBitmap(&bmi)) {
	//	m_Texture = Glyph3::RendererDX11::Get()->LoadTexture(bmi.bmBits, bmi.bmHeight * bmi.bmWidthBytes);
	//	m_pInputParameter->InitializeParameterData(&m_Texture->m_iResourceSRV);
	//}
	//else {
	//	// method 1) save to a file
	//	HRESULT hr = image.Save(_T("../Data/Textures/text.png"), ImageFormatPNG);
	//}

	m_fileName = L"../Data/Textures/text.png";
}

void CStudy_MFCView::OnLButtonDown(UINT nFlags, CPoint point)
{
	if (nFlags == MK_LBUTTON) {
		if (m_firstDown) { 
			m_lastMousePos = point; 
			m_firstDown = false;
			::SetCursor(AfxGetApp()->LoadStandardCursor(IDC_SIZEALL));
		}
	}
	Invalidate();
}

void CStudy_MFCView::OnLButtonUp(UINT nFlags, CPoint point)
{
	m_firstDown = true;
	::SetCursor(AfxGetApp()->LoadStandardCursor(IDC_ARROW));
	Invalidate();
}

void CStudy_MFCView::OnMouseMove(UINT nFlags, CPoint point)
{
	if (!m_firstDown) {
		if (nFlags == MK_LBUTTON) {
			m_deltaPt = m_lastMousePos - point;
			m_lastMousePos = point;

			WindowSize.x += m_deltaPt.x;
			WindowSize.y += m_deltaPt.y;
			WindowSize.x = WindowSize.x < 0 ? 0 : WindowSize.x;
			WindowSize.y = WindowSize.y < 0 ? 0 : WindowSize.y;
			m_pWindowSizeParameter->InitializeParameterData(&WindowSize);
			::SetCursor(AfxGetApp()->LoadStandardCursor(IDC_SIZEALL));
			Invalidate();
		}
	}
}

void CStudy_MFCView::OnSize(UINT nType, int cx, int cy)
{
	if (SwapChain >= 0 ) {
		Glyph3::RendererDX11::Get()->ResizeSwapChain(SwapChain, cx, cy);
		Glyph3::RendererDX11::Get()->ResizeTexture(m_DepthTarget, cx, cy);
		m_pColorSmoothView->Resize(cx, cy);
		pTextOverlayView->Resize(cx, cy);
		pCamera->SetAspectRatio(static_cast<float>(cx) / static_cast<float>(cy));
		pCamera->SetOrthographicParams(0.1f, 1000.0f, (float)cx, (float)cy);

		//// update WindowSize so that discrete path shader knows the boundary
		//WindowSize.z = cx;
		//WindowSize.w = cy;
		//m_pWindowSizeParameter->InitializeParameterData(&WindowSize);
	}
}

int CStudy_MFCView::GetSwapChain()
{
	return SwapChain;
}

void CStudy_MFCView::OnDestroy()
{
	if (m_pTimer) {
		delete m_pTimer;
	}
}

// CStudy_MFCView diagnostics

#ifdef _DEBUG
void CStudy_MFCView::AssertValid() const
{
	CView::AssertValid();
}

void CStudy_MFCView::Dump(CDumpContext& dc) const
{
	CView::Dump(dc);
}

CStudy_MFCDoc* CStudy_MFCView::GetDocument() const // non-debug version is inline
{
	ASSERT(m_pDocument->IsKindOf(RUNTIME_CLASS(CStudy_MFCDoc)));
	return (CStudy_MFCDoc*)m_pDocument;
}
#endif //_DEBUG

BOOL CStudy_MFCView::OnMouseWheel(UINT nFlags, short zDelta, CPoint pt)
{
	short delta = zDelta / WHEEL_DELTA;
	CStudy_MFCDoc* pDoc = GetDocument();
	ASSERT_VALID(pDoc);
	if (!pDoc)
		return FALSE;
	FLOAT maglevel = pDoc->m_fontData.magnifyLevel + (int)delta * 1.0;
	if (maglevel < 1) maglevel = 1;
	if (maglevel > FontData::MaxMagnifyLevel()) maglevel = FontData::MaxMagnifyLevel();
	pDoc->m_fontData.magnifyLevel = maglevel;
	MagnifyCoefficient = Glyph3::Vector2f((float)maglevel, (float)maglevel);
	m_pMagnifyParameter->InitializeParameterData(&MagnifyCoefficient);

	m_pColorSmoothView->SetMagnifyLevel(maglevel);
	Invalidate(FALSE);
	return TRUE;
}

//BOOL CStudy_MFCView::OnSetCursor(CWnd* pWnd, UINT nHitTest, UINT message)
//{
//	//if (!m_firstDown) {
//	//	::SetCursor(AfxGetApp()->LoadStandardCursor(IDC_SIZEALL));
//	//	return TRUE;
//	//}
//	return CWnd::OnSetCursor(pWnd, nHitTest, message);
//}

// CStudy_MFCView message handlers


void CStudy_MFCView::OnFileOpen()
{
	// load a new texture image
	WCHAR szFilters[] = L"Image files (*.png) | *.png|Image files (*.bmp)|*.bmp|All Files (*.*)|*.*||";
	CFileDialog fileDlg(TRUE, L"Image files", L"*.bmp", OFN_FILEMUSTEXIST | OFN_EXPLORER, szFilters, this);


	//CString szDirectory;
	if (m_dirName.IsEmpty()) { 
		WCHAR	szDirectory[MAX_PATH];
		::GetCurrentDirectory(sizeof(szDirectory) - 1, szDirectory); 
		m_dirName = CString(szDirectory);
	}
	
	fileDlg.m_pOFN->lpstrInitialDir = (LPCTSTR)m_dirName;
	
	if (fileDlg.DoModal() == IDOK)
	{
		m_fileName = fileDlg.GetFileName();
		m_dirName = fileDlg.GetPathName();
		m_fileName = m_dirName;
		int id = m_dirName.ReverseFind(L'\\');
		m_dirName = m_dirName.Left(id);
		LoadTextImage();
		Invalidate();
	}
}
